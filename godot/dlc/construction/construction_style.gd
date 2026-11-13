class_name ConstructionStyle
extends RefCounted
## The Construction DLC look, drawn in code (no image files): hazard-stripe yellow and black, and a padlock.
## Used by the title banner (scripts/main.gd), the hub (construction_hub.gd) and the code sheet.

const YELLOW := Color("#ffc21a")
const YELLOW_HI := Color("#ffd24d")
const YELLOW_DK := Color("#c98f00")
const BLACK := Color("#14120b")

## Diagonal black / yellow warning tape filling its rectangle.
class Hazard extends Control:
	var stripe := 14.0
	func _init() -> void:
		clip_contents = true
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _ready() -> void:
		resized.connect(queue_redraw)
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), ConstructionStyle.YELLOW)
		var h := size.y
		var x := -h
		while x < size.x:
			draw_colored_polygon(PackedVector2Array([Vector2(x, h), Vector2(x + stripe, h), Vector2(x + stripe + h, 0.0), Vector2(x + h, 0.0)]), ConstructionStyle.BLACK)
			x += stripe * 2.0

## A small padlock (shackle, body, keyhole).
class Padlock extends Control:
	var col := Color(1, 1, 1, 0.92)
	func _init() -> void:
		custom_minimum_size = Vector2(30, 36)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var w := size.x
		var h := size.y
		draw_arc(Vector2(w * 0.5, h * 0.4), w * 0.27, PI, TAU, 18, col, 4.0, true)
		draw_line(Vector2(w * 0.23, h * 0.4), Vector2(w * 0.23, h * 0.52), col, 4.0)
		draw_line(Vector2(w * 0.77, h * 0.4), Vector2(w * 0.77, h * 0.52), col, 4.0)
		draw_rect(Rect2(w * 0.08, h * 0.5, w * 0.84, h * 0.46), col)
		draw_circle(Vector2(w * 0.5, h * 0.7), w * 0.09, Color(0.1, 0.17, 0.2))
		draw_rect(Rect2(w * 0.46, h * 0.7, w * 0.08, h * 0.14), Color(0.1, 0.17, 0.2))

## A yellow box with a thick black frame and a darker lip (the banner, normal / hover / pressed).
static func tape_box(bg: Color, lip := 6) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(12)
	s.border_color = BLACK
	s.set_border_width_all(3)
	s.border_width_bottom = 3 + lip
	s.shadow_color = UiTheme.SHADOW
	s.shadow_size = 6
	s.shadow_offset = Vector2(0, 3)
	s.anti_aliasing = true
	s.corner_detail = 10
	return s
