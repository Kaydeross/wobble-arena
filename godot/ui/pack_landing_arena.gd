class_name PackLandingArena
extends Control
## The arena preview of a pack landing page: a still top-down thumbnail drawn in code from the arena's own boxes (the pack's
## generator, PackMaps.generate, or the map table entry for Construction's yard). Built once per pack and seed and redrawn only
## when the control is resized: no SubViewport, nothing per frame. Box colours are the arena's own; taller boxes are a little lighter.

var pack_id := ""
var floor_col := Color(0.2, 0.2, 0.22)
var frame_col := Color(1, 1, 1)
var _half := 24.0
var _items: Array = []            ## [Rect2 (arena metres: x, z, w, d), Color], lowest first

func _init() -> void:
	name = "ArenaThumb"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(40, 40)

static func map_for(arena_id: String, sd: int) -> Dictionary:
	if PackMaps.has(arena_id): return PackMaps.generate(arena_id, sd)
	var maps: Variant = Content.maps
	if maps is Dictionary and (maps as Dictionary).has(arena_id): return (maps as Dictionary)[arena_id]
	return {}

## Reads the boxes of `m` (a map entry); an empty map leaves the thumbnail blank.
func set_map(m: Dictionary) -> void:
	_items.clear()
	var g: Dictionary = m.get("geometry", {})
	var boxes: Array = g.get("boxes", [])
	if boxes.is_empty():
		queue_redraw()
		return
	var fl: Dictionary = boxes[0]
	_half = maxf(float(fl.get("w", 48.0)), float(fl.get("d", 48.0))) * 0.5
	floor_col = _col(int(fl.get("color", 0x333338)), 0.0)
	var tall: Array = []
	for i in range(1, boxes.size()):
		var b: Dictionary = boxes[i]
		var h := float(b.get("h", 0.0))
		var top := float(b.get("y", 0.0)) + h
		if h < 0.12 and top < 0.1 and i > 0 and float(b.get("w", 0.0)) < 1.0: continue     # lane lines
		var rr := Rect2(float(b.get("x", 0.0)) - float(b.get("w", 0.0)) * 0.5, float(b.get("z", 0.0)) - float(b.get("d", 0.0)) * 0.5, float(b.get("w", 0.0)), float(b.get("d", 0.0)))
		tall.append([top, rr, _col(int(b.get("color", 0x888888)), clampf(top / 6.0, 0.0, 0.35))])
	tall.sort_custom(func(a: Array, c: Array) -> bool: return float(a[0]) < float(c[0]))
	for e: Array in tall: _items.append([e[1], e[2]])
	queue_redraw()

static func _col(c: int, lift: float) -> Color:
	return Color.hex((c << 8) | 0xff).lightened(lift)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED: queue_redraw()

func box_count() -> int:
	return _items.size()

func _draw() -> void:
	var s := minf(size.x, size.y)
	if s < 8.0: return
	var o := (size - Vector2(s, s)) * 0.5
	var k := s / (_half * 2.0)
	var r := Rect2(o, Vector2(s, s))
	draw_rect(r, floor_col)
	for it: Array in _items:
		var q: Rect2 = it[0]
		var rr := Rect2(o + (q.position + Vector2(_half, _half)) * k, q.size * k)
		if rr.size.x < 0.6: rr.size.x = 0.6
		if rr.size.y < 0.6: rr.size.y = 0.6
		draw_rect(rr, it[1])
	draw_rect(r, frame_col, false, 2.0)
