class_name FighterJuice
extends RefCounted
## Squash and stretch, hit squeeze and the hitstop pose freeze, PRESENTATION ONLY, layered on top of whatever the
## wobbler shows (classic pose or the ragdoll overlay, docs/RAGDOLL.md). Fighter.present calls restore() first (puts
## back exactly the node transforms apply() changed, so animate() and the gameplay points read from the classic pose
## never see it) and apply() last, after the overlay.
##   landing   squash spring kicked by the landing speed (overshoots into a little stretch: a bounce)
##   jump      a stretch kick on take-off, a slight stretch along the vertical speed while airborne
##   hit       a short squeeze from the lean kick of a blow
##   frozen    hitstop: the visible pose is held for a few frames (the sim and animate() keep running underneath)

const K := 280.0                     ## spring stiffness (1/s^2)
const C := 13.0                      ## damping (1/s)

var sq := 0.0                        ## + = squashed (shorter, wider), - = stretched
var sq_v := 0.0
var hit_k := 0.0
var was_g := true
var prev_vy := 0.0
var _nodes: Array[Node3D] = []
var _saved: Array[Transform3D] = []
var _held: Array[Transform3D] = []
var _active := false

func restore() -> void:
	if not _active: return
	for i in _nodes.size():
		_nodes[i].transform = _saved[i]
	_active = false

## A blow's lean kick (Combat `lean` a / b).
func kick(a: float, b: float) -> void:
	hit_k = maxf(hit_k, clampf(Vector2(a, b).length() * 0.035, 0.0, 0.2))

func apply(w: Wobbler, dt: float, frozen: bool) -> void:
	if _nodes.is_empty():
		_nodes = w._xf_nodes.duplicate()
		_saved.resize(_nodes.size())
	if not frozen and dt > 0.0:
		var g: bool = w.grounded
		var vy: float = w.vel.y
		if g and not was_g and prev_vy < -5.0 and not w.dead:
			sq_v += minf(7.5, -prev_vy * 0.42)
		elif not g and was_g and vy > 3.0:
			sq_v -= 3.2
		was_g = g
		prev_vy = vy
		sq_v += (-K * sq - C * sq_v) * dt
		sq += sq_v * dt
		sq = clampf(sq, -0.22, 0.32)
		hit_k = maxf(0.0, hit_k - dt * 1.6)
	var air := 0.0 if w.grounded else clampf(w.vel.y * 0.006, -0.05, 0.06)
	var s := sq - air + hit_k * 0.6
	if not frozen:
		_held.clear()
		if absf(s) < 0.003 and hit_k < 0.003: return
	for i in _nodes.size():
		_saved[i] = _nodes[i].transform
	_active = true
	if frozen:
		if _held.is_empty():
			_held.resize(_nodes.size())
			for i in _nodes.size(): _held[i] = _saved[i]
		for i in _nodes.size(): _nodes[i].transform = _held[i]
		return
	var sy := 1.0 - s
	var sxz := 1.0 + s * 0.55
	w.rig.basis = w.rig.basis.scaled_local(Vector3(sxz, sy, sxz))
