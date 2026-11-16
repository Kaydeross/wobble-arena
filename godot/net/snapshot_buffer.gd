class_name SnapshotBuffer
extends RefCounted
## A small, bounded interpolation buffer for one remote fighter (WP 1.0-B, docs/PROTOCOL.md 3.1).
##
## Snapshots arrive at 30 Hz with jitter. Drawing a remote fighter at `clock - DELAY` gives the buffer a
## snapshot on both sides of the render time, so the ghost slides between two real positions instead of
## being carried forward from the newest one. When there is no snapshot old enough yet the earliest kept
## position is held (no backwards jump at the start / after a rejoin); when the newest snapshot is older
## than the render time NetMatch falls back to the existing <= PREDICT_MAX extrapolation.
##
## The buffer is presentation only: hits still resolve against the authoritative simulation positions it
## feeds. It is bounded (MAX snapshots, ~4 x the render delay at 30 Hz) and a snapshot whose arrival clock
## is not newer than the last accepted one is dropped, so a late or reordered packet can never be drawn.

const DELAY := 0.1          ## seconds a remote fighter is drawn behind the local clock
const MAX := 8              ## snapshots kept per fighter: 8 x 33 ms = 0.27 s of history at 30 Hz

var _t: Array[float] = []   ## arrival clock of each kept snapshot, ascending
var _p: Array = []          ## [x, y, z] of each kept snapshot, same order
var _last := -1.0           ## arrival clock of the newest accepted snapshot

## Drop every snapshot (a rejoin / a seat that became a bot).
func clear() -> void:
	_t.clear(); _p.clear(); _last = -1.0

## How many snapshots are kept (tests: bounded).
func size() -> int:
	return _t.size()

## Keep one decoded `S` entry that arrived at `clock`. Returns false (and keeps nothing) for a late or
## out-of-order packet: remote drawing never moves backwards because of one.
func push(clock: float, e: Dictionary) -> bool:
	if not (e.get("x") is float or e.get("x") is int) or not (e.get("z") is float or e.get("z") is int): return false
	if clock <= _last: return false
	_last = clock
	_t.append(clock)
	_p.append([float(e["x"]), float(e.get("y", 0.0)), float(e["z"])])
	while _t.size() > MAX:
		_t.remove_at(0); _p.remove_at(0)
	return true

## The position to draw at `now` (the local clock), or [] when the buffer cannot bracket `now - DELAY`.
## [] means "no snapshot old enough": the caller does the <= 0.2 s extrapolation fallback. Before the
## first pair brackets the render time the earliest position is held, so the ghost never jumps backwards.
func sample(now: float) -> Array:
	if _p.is_empty(): return []
	var render_t := now - DELAY
	if render_t <= _t[0]: return (_p[0] as Array).duplicate()
	if render_t >= _t[_t.size() - 1]: return []
	var i := _t.size() - 2
	for k in _t.size():
		if _t[k] <= render_t:
			i = k
		else:
			break
	var span := _t[i + 1] - _t[i]
	var u := 0.0 if span <= 0.0 else clampf((render_t - _t[i]) / span, 0.0, 1.0)
	var a: Array = _p[i]
	var b: Array = _p[i + 1]
	return [a[0] + (b[0] - a[0]) * u, a[1] + (b[1] - a[1]) * u, a[2] + (b[2] - a[2]) * u]
