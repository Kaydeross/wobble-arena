extends Control
## Floating nameplates over other fighters, like the web game's compact HUD (updateTags): only the 3 nearest
## fighters in front of the camera and within 45 m, faded by distance, as a teal pill with the name and a health
## bar that eases toward the real value. `sim` and `cam` are set by hud.gd.

const MAX_SHOWN := 3
const MAX_DIST := 45.0
const LIFT := 2.6              ## metres above the feet for a size-1 class (web: pos.y + 2.5)

var sim: MatchSim
var cam: Camera3D
var _shown_hp := {}            ## FighterState -> eased hp fraction
var _plates: Array = []        ## [screen pos, alpha, name, hp, colour]
var _font: Font

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_font = UiTheme.font(700)

func tick(dt: float) -> void:
	_plates.clear()
	if sim == null or cam == null or not cam.is_inside_tree():
		queue_redraw(); return
	var near: Array = []
	var cp := cam.global_position
	for f: FighterState in sim.fighters:
		if f == sim.player or f.dead or f.left: continue
		var sz := float(sim.combat.classes.get(f.class_id, {}).get("size", 1.0))
		var wp := Vector3(f.phys.px, f.phys.py + LIFT * sz, f.phys.pz)
		var d := cp.distance_to(Vector3(f.phys.px, f.phys.py, f.phys.pz))
		if d > MAX_DIST or cam.is_position_behind(wp): continue
		near.append([d, f, wp])
	near.sort_custom(func(a, b): return a[0] < b[0])
	var keep := {}
	var vs := get_viewport_rect().size
	for n: Array in near.slice(0, MAX_SHOWN):
		var f: FighterState = n[1]
		var sp := cam.unproject_position(n[2])
		if sp.x < -60 or sp.x > vs.x + 60 or sp.y < -40 or sp.y > vs.y + 40: continue
		var k := clampf(f.hp / maxf(sim.combat.max_hp(f), 1.0), 0.0, 1.0)
		var s: float = _shown_hp.get(f, k)
		s = lerpf(s, k, 1.0 - exp(-dt * 8.0))
		_shown_hp[f] = s
		keep[f] = true
		var alpha := clampf(1.5 - float(n[0]) / 22.0, 0.3, 1.0)
		_plates.append([sp, alpha, Safety.display_name(f.name), s, Color.hex((int(sim.looks.get(f, {}).get("color", 0xffffff)) << 8) | 0xff)])
	for f in _shown_hp.keys():
		if not keep.has(f): _shown_hp.erase(f)
	_spread()
	queue_redraw()

## Nearest plates keep their spot; farther ones that would overlap are pushed up above them.
func _spread() -> void:
	var placed: Array = []
	for p: Array in _plates:
		var r := _rect(p)
		var moved := true
		var guard := 0
		while moved and guard < 6:
			moved = false; guard += 1
			for q: Rect2 in placed:
				if r.grow(2.0).intersects(q):
					r.position.y = q.position.y - r.size.y - 4.0
					moved = true
		p[0] = Vector2(p[0].x, r.end.y + 2.0)
		placed.append(r)

func _plate_w(name: String) -> float:
	return maxf(_font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 30.0, 74.0)

func _rect(p: Array) -> Rect2:
	var w := _plate_w(p[2])
	return Rect2(p[0].x - w / 2.0, p[0].y - 34.0, w, 32.0)

func _draw() -> void:
	for p: Array in _plates:
		var sp: Vector2 = p[0]
		var a: float = p[1]
		var name: String = p[2]
		var k: float = p[3]
		var col: Color = p[4]
		var fs := 15
		var tw := _font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var r := _rect(p)
		var w := r.size.x
		var sb := UiTheme.box(Color(UiTheme.PANEL.r, UiTheme.PANEL.g, UiTheme.PANEL.b, 0.72 * a), 16, Color(1, 1, 1, 0.22 * a), 2, 3)
		sb.shadow_color = Color(0, 0, 0, 0.25 * a)
		draw_style_box(sb, r)
		# colour dot (the fighter's body colour) + name
		draw_circle(Vector2(r.position.x + 12, r.position.y + 12), 4.0, Color(col.r, col.g, col.b, a))
		draw_string(_font, Vector2(r.position.x + 20 + (w - 26 - tw) / 2.0, r.position.y + 17), name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, a))
		var bar := Rect2(r.position.x + 10, r.position.y + 22, w - 20, 5)
		draw_rect(bar, Color(0, 0, 0, 0.5 * a))
		var hc := preload("res://ui/hud_health.gd").hp_color(k)
		hc.a = a
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * k, bar.size.y)), hc)
		# little pointer under the pill
		draw_colored_polygon(PackedVector2Array([Vector2(sp.x - 6, r.end.y - 1), Vector2(sp.x + 6, r.end.y - 1), Vector2(sp.x, r.end.y + 6)]),
			Color(UiTheme.PANEL.r, UiTheme.PANEL.g, UiTheme.PANEL.b, 0.72 * a))
