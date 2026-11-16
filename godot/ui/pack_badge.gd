class_name PackBadge
extends Control
## A DLC pack's small badge: its hat drawn from rects, circles and polygons (no assets), on a rounded tile in the pack's
## colour. "hardhat" (Construction), "chef" (On Fire: the toque), "santa" (Ho Ho Ho) and "cork" (Hey Mate: the slouch hat
## with its dangling corks). Used by the title showcase header, the hub's pack cards and the setup wizard's icons; the data
## says which one (DLCPackData.badge_kind()). An unknown kind draws a plain disc.

var kind := ""
var col := Color("#ffc21a")
var locked := false                 ## dimmed, with a small padlock (the pack is not owned)

func _init(k: String = "", c: Color = Color("#ffc21a"), px: float = 44.0) -> void:
	kind = k
	col = c
	custom_minimum_size = Vector2(px, px)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_locked(on: bool) -> void:
	locked = on
	queue_redraw()

func _p(x: float, y: float) -> Vector2:
	return Vector2(x, y) * size.x

func _poly(pts: Array, c: Color) -> void:
	var a := PackedVector2Array()
	for q: Vector2 in pts: a.append(_p(q.x, q.y))
	draw_colored_polygon(a, c)

func _rect(x: float, y: float, w: float, h: float, c: Color) -> void:
	draw_rect(Rect2(_p(x, y), _p(w, h)), c)

func _dome(cx: float, cy: float, r: float, c: Color) -> void:
	var pts: Array = []
	for i in 13:
		var a := PI + PI * i / 12.0
		pts.append(Vector2(cx, cy) + Vector2(cos(a), sin(a)) * r)
	_poly(pts, c)

func _draw() -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = col.darkened(0.62)
	bg.bg_color.a = 0.92
	bg.border_color = col
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(int(size.x * 0.26))
	draw_style_box(bg, Rect2(Vector2.ZERO, size))
	var ink := Color(0.0627, 0.1686, 0.2078)
	var white := Color("#f4f1ea")
	match kind:
		"hardhat":
			_dome(0.5, 0.62, 0.3, col.lightened(0.1))
			_rect(0.14, 0.62, 0.72, 0.1, col)
			_rect(0.45, 0.28, 0.1, 0.34, col.darkened(0.25))
		"chef":
			for x in [0.3, 0.5, 0.7]: draw_circle(_p(x, 0.4), size.x * 0.17, white)    # the puffed toque
			draw_circle(_p(0.5, 0.3), size.x * 0.19, white)
			_rect(0.28, 0.46, 0.44, 0.26, white)
			_rect(0.28, 0.66, 0.44, 0.07, col)
		"santa":
			_poly([Vector2(0.2, 0.7), Vector2(0.34, 0.3), Vector2(0.66, 0.2), Vector2(0.8, 0.7)], Color("#e0353a"))
			_rect(0.16, 0.64, 0.68, 0.14, white)
			draw_circle(_p(0.7, 0.2), size.x * 0.09, white)
		"cork":
			_dome(0.5, 0.58, 0.27, Color("#c89a5b"))
			_rect(0.12, 0.58, 0.76, 0.09, Color("#a87a3c"))
			_rect(0.3, 0.5, 0.4, 0.06, ink)
			for x in [0.26, 0.4, 0.54, 0.68]:      # the corks on strings
				draw_line(_p(x, 0.67), _p(x, 0.8), white, size.x * 0.02)
				_rect(x - 0.03, 0.79, 0.06, 0.09, Color("#d8b27a"))
		_:
			draw_circle(_p(0.5, 0.5), size.x * 0.25, col.lightened(0.2))
	if locked:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.35))
