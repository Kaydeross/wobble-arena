class_name Hazard
extends RefCounted
## Construction-site hazard tape: diagonal yellow / black stripes. Shared by the "DON'T ENTER" sign and the wipe
## transition of the Construction DLC title.

const YELLOW := Color(1.0, 0.82, 0.08)
const BLACK := Color(0.09, 0.08, 0.07)

## Fills `r` on `ci` with "/" stripes of width `band`, scrolled by `shift` pixels. Stripes are clipped to `r`.
static func stripes(ci: CanvasItem, r: Rect2, band: float = 22.0, shift: float = 0.0, a: Color = YELLOW, b: Color = BLACK) -> void:
	if r.size.x <= 0.0 or r.size.y <= 0.0: return
	ci.draw_rect(r, a)
	var step := band * 2.0
	var h := r.size.y
	var n := int((r.size.x + h) / step) + 3
	var x0 := r.position.x - h - fposmod(shift, step)
	var rp := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	for i in n:
		var x := x0 + i * step
		var pts := PackedVector2Array([Vector2(x, r.end.y), Vector2(x + band, r.end.y), Vector2(x + band + h, r.position.y), Vector2(x + h, r.position.y)])
		for poly: PackedVector2Array in Geometry2D.intersect_polygons(pts, rp):
			if poly.size() >= 3 and absf(_area(poly)) > 1.0:   # skip slivers the triangulator rejects
				ci.draw_colored_polygon(poly, b)

static func _area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		a += p.x * q.y - q.x * p.y
	return a * 0.5
