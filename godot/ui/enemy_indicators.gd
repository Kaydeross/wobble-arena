extends Control
## Off-screen enemy indicators (playtest request: "show small enemy indicator on screen to let user easily find even
## they are on the back"). For every living hostile fighter outside the current camera view (behind the camera, above
## or below the view, or just outside the frustum) a small arrow sits on the inside edge of the safe area pointing
## that way; an enemy that is on screen gets no arrow. Up to MAX_MARKERS of the nearest are shown, tinted with the
## fighter's body (or team) colour, fading with distance. Arrow positions are laid out along the rim: a marker that
## would sit on top of another one (several enemies close together) slides along the edge and fades, and a marker that
## would cover a HUD panel or a touch button slides past it (the rim rect and the blocked rects come from hud.gd).
## Every node is pooled once in _ready (no per-frame nodes, no leaks) and Settings > Gameplay > `enemy_arrows` (default
## on) shows or hides the whole layer. `sim`, `cam` and `enabled` are set by hud.gd; `tick(delta, rim, blocked)` runs
## from MatchHud.update, after the HUD panels have been placed (so their rects are this frame's).

const MAX_MARKERS := 6        ## nearest enemies shown; the rest stay unmarked (unobtrusive)
const MARKER := 26.0          ## square canvas px of one pooled marker Control (the arrow is drawn inside it)
const MIN_SEP := 32.0         ## canvas px along the rim between two markers (clustered enemies spread out)
const MAX_SLIDE := 12         ## slot searches each way along the rim before an enemy is skipped
const ON_SCREEN_PAD := 4.0    ## canvas px: a projected fighter this close to the view edge counts as on screen
const BODY_LIFT := 1.2        ## metres above the feet the marker is aimed at (mid-body)
const FAR_FADE := 55.0        ## metres to the dimmest marker
const NUDGED_FADE := 0.8      ## alpha multiplier for a marker that had to slide away from another one

var sim: MatchSim
var cam: Camera3D
var enabled := true            ## Settings `enemy_arrows` (and not paused / results) — set by hud.gd each frame
var stage := Rect2()           ## the rim, in canvas px; set by hud.gd (the safe area inset by hud.IND_PAD)
var markers: Array = []        ## the fixed pool: MAX_MARKERS Controls, pooled once in _ready
var shown := 0                 ## markers visible after the last tick (tests read this)

const SIDES := [1.0, -1.0]     ## slot search directions along the rim (shared, so a tick allocates no array)

var _cand: Array = []          ## this frame's off-screen fighters, nearest first (reused, never re-created)
var _used: Array = []          ## rim slots taken this frame (perimeter px, reused)
var _blocked: Array = []       ## the HUD's rects this frame (a reference to hud.gd's reused array)
var _by_dist: Callable

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_by_dist = _closer
	for i in MAX_MARKERS:
		var m := Control.new()
		m.name = "Marker%d" % i
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		m.size = Vector2(MARKER, MARKER)
		m.visible = false
		m.draw.connect(_draw_marker.bind(m))
		add_child(m)
		markers.append(m)

## One HUD update: `rim` is the canvas-space rect the arrows sit on, `blocked` the screen rects they must not cover.
func tick(_delta: float, rim: Rect2, blocked: Array) -> void:
	shown = 0
	if not enabled or sim == null or cam == null or not cam.is_inside_tree() or rim.size.x < 80.0 or rim.size.y < 80.0:
		for m: Control in markers: m.visible = false
		_cand.clear()
		return
	stage = rim
	_blocked = blocked
	_cand.clear()
	var centre := stage.get_center()
	for f: FighterState in sim.fighters:
		if f == sim.player or f.dead or f.left or f.elim: continue    # living, still in
		if _friendly(f): continue                                      # teammates in team modes / Arcade co-op seats
		var wp := _aim_point(f)
		if _on_screen(wp): continue
		_cand.append(f)
	if _cand.size() > 1: _cand.sort_custom(_by_dist)
	var n := mini(_cand.size(), MAX_MARKERS)
	_used.clear()
	for i in n:
		var f: FighterState = _cand[i]
		var wp := _aim_point(f)
		var d := cam.global_position.distance_to(Vector3(f.phys.px, f.phys.py, f.phys.pz))
		var dir := _screen_dir(wp)
		var want := _t_of(dir)
		var got := _free_t(want)
		if got < 0.0: continue
		var slid := _rim_dist(want, got)
		_used.append(got)
		var p := _point(got)
		var m: Control = markers[shown]
		m.position = p - Vector2(MARKER, MARKER) * 0.5
		m.set_meta("dir", (p - centre).normalized() if p != centre else dir)
		m.set_meta("tint", _tint(f))
		m.set_meta("size_k", lerpf(1.0, 0.78, clampf(d / FAR_FADE, 0.0, 1.0)))   # distance band: nearer arrows read bigger
		var a := clampf(1.12 - d / FAR_FADE, 0.5, 1.0)
		if slid > 0.5: a *= NUDGED_FADE
		m.modulate = Color(1, 1, 1, a)
		m.visible = true
		m.queue_redraw()
		shown += 1
	for i in range(shown, MAX_MARKERS):
		(markers[i] as Control).visible = false

## Is a fighter a teammate (no arrow)? Team modes: same team. Arcade: the other player seat in co-op.
func _friendly(f: FighterState) -> bool:
	if sim.combat == null: return false
	if sim.combat.teams != 0 and f.team == sim.player.team: return true
	return not sim.combat.pve_seats.is_empty() and sim.combat.pve_seats.has(f)

func _aim_point(f: FighterState) -> Vector3:
	return Vector3(f.phys.px, f.phys.py + BODY_LIFT, f.phys.pz)

func _closer(a: FighterState, b: FighterState) -> bool:
	var cp := cam.global_position
	return cp.distance_squared_to(Vector3(a.phys.px, a.phys.py, a.phys.pz)) \
		< cp.distance_squared_to(Vector3(b.phys.px, b.phys.py, b.phys.pz))

## True when the fighter is inside the camera's view: in front of the near plane and projected inside the viewport
## (plus ON_SCREEN_PAD). A fighter behind the camera never counts, even if its mirrored projection lands on screen.
func _on_screen(wp: Vector3) -> bool:
	var lp := cam.global_transform.affine_inverse() * wp
	if lp.z > -0.02: return false
	var sp := cam.unproject_position(wp)
	var vs := get_viewport_rect().size
	return Rect2(Vector2(-ON_SCREEN_PAD, -ON_SCREEN_PAD), vs + Vector2(ON_SCREEN_PAD, ON_SCREEN_PAD) * 2.0).has_point(sp)

## Screen direction from the rim centre towards the fighter. In front: the projected direction (correct for above /
## below / side). Behind: the camera-space direction (screen x = camera right, screen y = world down), which is the
## side the player has to turn towards; an enemy dead behind (0, 0) points at the bottom edge.
func _screen_dir(wp: Vector3) -> Vector2:
	var lp := cam.global_transform.affine_inverse() * wp
	if lp.z < -0.02:
		var d := cam.unproject_position(wp) - stage.get_center()
		if d.length_squared() > 1.0: return d.normalized()
	var d2 := Vector2(lp.x, -lp.y)
	if d2.length_squared() < 0.0001: d2 = Vector2(0.0, 1.0)
	return d2.normalized()

# ---------------- rim layout ----------------

func _perimeter() -> float:
	return 2.0 * (stage.size.x + stage.size.y)

## Perimeter coordinate (0 = top-left corner, clockwise) of the point where `dir` leaves the rim.
func _t_of(dir: Vector2) -> float:
	var half := stage.size * 0.5
	var c := stage.position + half
	var s := minf(half.x / maxf(absf(dir.x), 1e-6), half.y / maxf(absf(dir.y), 1e-6))
	var p := c + dir * s
	var w := stage.size.x
	var h := stage.size.y
	if absf(p.y - stage.position.y) < 0.01: return p.x - stage.position.x
	if absf(p.x - stage.end.x) < 0.01: return w + p.y - stage.position.y
	if absf(p.y - stage.end.y) < 0.01: return w + h + stage.end.x - p.x
	return 2.0 * w + h + stage.end.y - p.y

## Canvas point on the rim at perimeter coordinate `t` (wrapped).
func _point(t: float) -> Vector2:
	var w := stage.size.x
	var h := stage.size.y
	t = fposmod(t, 2.0 * (w + h))
	if t < w: return Vector2(stage.position.x + t, stage.position.y)
	t -= w
	if t < h: return Vector2(stage.end.x, stage.position.y + t)
	t -= h
	if t < w: return Vector2(stage.end.x - t, stage.end.y)
	t -= w
	return Vector2(stage.position.x, stage.end.y - t)

func _rim_dist(a: float, b: float) -> float:
	var d := absf(a - b)
	return minf(d, _perimeter() - d)

## The nearest free rim slot for `want`: at least MIN_SEP from an already placed marker and clear of `_blocked`.
## Returns -1.0 when every nearby slot is taken (that enemy is not shown this frame).
func _free_t(want: float) -> float:
	var p := _perimeter()
	for k in MAX_SLIDE + 1:
		for side: float in SIDES:
			var t := fposmod(want + side * float(k) * MIN_SEP, p)
			if _slot_free(t): return t
	return -1.0

func _slot_free(t: float) -> bool:
	var centre := _point(t)
	var r := Rect2(centre - Vector2(MARKER, MARKER) * 0.5, Vector2(MARKER, MARKER))
	for b: Rect2 in _blocked:
		if r.grow(2.0).intersects(b): return false
	for q: float in _used:
		if _rim_dist(t, q) < MIN_SEP: return false
	return true

# ---------------- drawing ----------------

## The arrow itself: a small triangle pointing along `dir`, body colour, ink outline, a white pip so it reads on any
## map colour. `modulate.a` carries the distance / crowding fade.
func _draw_marker(m: Control) -> void:
	var dir: Vector2 = m.get_meta("dir", Vector2.DOWN)
	var tint: Color = m.get_meta("tint", UiTheme.ACCENT)
	var k: float = m.get_meta("size_k", 1.0)
	var c := m.size * 0.5
	var d := dir.normalized()
	var perp := Vector2(-d.y, d.x)
	var r := (MARKER * 0.5 - 1.0) * k
	m.draw_circle(c, r * 0.82, Color(UiTheme.INK.r, UiTheme.INK.g, UiTheme.INK.b, 0.35))
	var apex := c + d * r
	var base := c - d * (r * 0.55)
	var wing := perp * (r * 0.72)
	var tri := PackedVector2Array([apex, base + wing, base - wing])
	m.draw_colored_polygon(tri, tint)
	m.draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), Color(UiTheme.INK.r, UiTheme.INK.g, UiTheme.INK.b, 0.9), 1.5, true)
	m.draw_circle(c - d * (r * 0.2), r * 0.18, Color(1, 1, 1, 0.92))

## The fighter's body colour (like the nameplates), or its team colour in team modes.
func _tint(f: FighterState) -> Color:
	if sim.combat != null and sim.combat.teams != 0:
		var tc := sim.combat.rules.team_color(f)
		if tc >= 0: return Color.hex((tc << 8) | 0xff)
	var look: Dictionary = sim.looks.get(f, {})
	return Color.hex((int(look.get("color", 0xffffff)) << 8) | 0xff)
