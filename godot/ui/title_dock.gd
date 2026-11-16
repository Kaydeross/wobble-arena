class_name TitleDock
extends PanelContainer
## The title's icon dock (scripts/main.gd, docs/TITLE.md): a compact glass panel at the bottom left with one icon tile
## and one short word per menu action (Quick play, Online, Walldrobe, Shop, Goals). Every item is a real Button (mouse,
## touch, keyboard, gamepad, screen reader) whose whole tile + word is the touch target. Icons are drawn from lines and
## polygons (no image files). `set_badge()` puts a small count on a tile (the Goals the player can claim).

const WORD_FONT := 16.0                ## canvas px: the words under the tiles (UiTheme.MIN_FONT is 14; 16 is about 11.7 pt on a phone)
const TILE := Vector2(63.0, 60.0)      ## canvas px: the icon tile (46 x 44 pt on a phone in landscape)
const PAD := 12.0

var row: HBoxContainer
var items: Dictionary = {}             ## node name -> DockItem

## One menu action: a transparent Button holding the icon tile and its word.
class DockItem extends Button:
	var tile: Tile
	var word: Label

	func _init(item_name: String, icon_kind: String, text_key: String) -> void:
		name = item_name
		flat = true
		focus_mode = Control.FOCUS_ALL
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for st: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			add_theme_stylebox_override(st, StyleBoxEmpty.new())
		var f := UiTheme.box(Color.TRANSPARENT, 16, Color.WHITE, 3, 0)
		f.draw_center = false
		add_theme_stylebox_override("focus", f)
		var st := VBoxContainer.new()
		st.name = "Stack"
		st.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		st.mouse_filter = Control.MOUSE_FILTER_IGNORE
		st.alignment = BoxContainer.ALIGNMENT_CENTER
		st.add_theme_constant_override("separation", 3)
		add_child(st)
		tile = Tile.new(icon_kind)
		st.add_child(tile)
		word = Label.new()
		word.name = "Word"
		word.text = text_key
		word.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		word.mouse_filter = Control.MOUSE_FILTER_IGNORE
		word.add_theme_font_size_override("font_size", int(WORD_FONT))
		word.add_theme_color_override("font_color", UiTheme.MUTED)
		word.add_theme_font_override("font", UiTheme.font(600))
		st.add_child(word)
		for s: Signal in [mouse_entered, mouse_exited, button_down, button_up, focus_entered, focus_exited]:
			s.connect(tile.queue_redraw)
		disabled = false

	func set_badge(n: int) -> void:
		tile.badge = n
		tile.queue_redraw()

## The rounded tile with the drawn glyph; it follows its parent button's hover / pressed / focus state.
class Tile extends Control:
	var kind := ""
	var badge := 0

	func _init(k: String) -> void:
		kind = k
		name = "Tile"
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = TILE
		size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		var b := get_parent().get_parent() as Button
		var mode := b.get_draw_mode() if b else BaseButton.DRAW_NORMAL
		var pressed := mode == BaseButton.DRAW_PRESSED or mode == BaseButton.DRAW_HOVER_PRESSED
		var hover := mode == BaseButton.DRAW_HOVER or mode == BaseButton.DRAW_HOVER_PRESSED
		var r := Rect2(Vector2(0, 2.0 if pressed else 0.0), size - Vector2(0, 2.0))
		var bg := UiTheme.PANEL_HI.lightened(0.12 if hover else 0.0)
		var sb := UiTheme.box(bg, 14, Color(1, 1, 1, 0.34 if hover else 0.22), 2, 0)
		draw_style_box(sb, r)
		_glyph(r)
		if badge > 0:
			var t := str(badge) if badge < 100 else "99"
			var f := UiTheme.font(700)
			var fs := 17
			var w := maxf(24.0, f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 14.0)
			var pill := Rect2(r.end.x - w * 0.62, r.position.y - 9.0, w, 26.0)
			var pb := UiTheme.box(UiTheme.ACCENT, 13, UiTheme.INK, 2, 0)
			draw_style_box(pb, pill)
			var tw := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(f, Vector2(pill.position.x + (w - tw) * 0.5, pill.position.y + 20.0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.INK)

	## Glyphs on a 24 x 24 grid scaled to the tile (the same shapes as the design mock).
	func _glyph(r: Rect2) -> void:
		var s := minf(r.size.x, r.size.y) * 0.5 / 12.0
		var o := r.get_center() - Vector2(12, 12) * s
		var col := UiTheme.ACCENT
		var w := 2.2 * s
		match kind:
			"quick":
				var pts := PackedVector2Array([Vector2(13.5, 2), Vector2(4.5, 14), Vector2(11, 14), Vector2(10, 22), Vector2(19, 9.5), Vector2(12.5, 9.5)])
				draw_colored_polygon(_map(pts, o, s), col)
			"online":
				draw_arc(o + Vector2(12, 12) * s, 9.0 * s, 0.0, TAU, 32, col, w, true)
				draw_line(o + Vector2(3, 12) * s, o + Vector2(21, 12) * s, col, w, true)
				for sx: float in [-1.0, 1.0]:
					var pl := PackedVector2Array()
					for i in 13:
						var a := lerpf(-PI * 0.5, PI * 0.5, float(i) / 12.0)
						pl.append(o + Vector2(12.0 + sx * cos(a) * 3.2, 12.0 + sin(a) * 9.0) * s)
					draw_polyline(pl, col, w, true)
			"wall":    # a coat hanger
				var pts := PackedVector2Array([Vector2(12, 8.2), Vector2(12, 11), Vector2(3.2, 17.5), Vector2(3.8, 19.3), Vector2(20.2, 19.3), Vector2(20.8, 17.5), Vector2(12, 11)])
				draw_polyline(_map(pts, o, s), col, w, true)
				draw_arc(o + Vector2(12, 7) * s, 2.2 * s, PI * 0.15, PI * 1.9, 14, col, w, true)
			"shop":    # a bag
				var body := PackedVector2Array([Vector2(5.2, 8), Vector2(18.8, 8), Vector2(19.8, 20), Vector2(4.2, 20), Vector2(5.2, 8)])
				draw_polyline(_map(body, o, s), col, w, true)
				draw_arc(o + Vector2(12, 8) * s, 3.3 * s, PI, TAU, 14, col, w, true)
			"goals":   # a target
				draw_arc(o + Vector2(12, 12) * s, 9.0 * s, 0.0, TAU, 32, col, w, true)
				draw_arc(o + Vector2(12, 12) * s, 4.8 * s, 0.0, TAU, 24, col, w, true)
				draw_circle(o + Vector2(12, 12) * s, 1.6 * s, col)

	static func _map(pts: PackedVector2Array, o: Vector2, s: float) -> PackedVector2Array:
		var out := PackedVector2Array()
		for p in pts: out.append(o + p * s)
		return out

func _init() -> void:
	name = "Dock"
	mouse_filter = Control.MOUSE_FILTER_PASS
	var sb := UiTheme.box(Color(UiTheme.PANEL.r, UiTheme.PANEL.g, UiTheme.PANEL.b, 0.78), 20, UiTheme.PANEL_EDGE, 2, 4)
	sb.content_margin_left = PAD; sb.content_margin_right = PAD; sb.content_margin_top = 10.0; sb.content_margin_bottom = 8.0
	add_theme_stylebox_override("panel", sb)
	row = HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", 12)
	add_child(row)

## Adds an item and returns its button (the owner connects `pressed`). `text_key` is the English word (translated on show).
func add_item(item_name: String, icon_kind: String, text_key: String) -> DockItem:
	var b := DockItem.new(item_name, icon_kind, text_key)
	row.add_child(b)
	items[item_name] = b
	return b

## Sizes every item to its word (at least as wide as the tile) and returns the dock's size. `k` scales it (the 60 px
## touch target must stay 44 pt: UiScale does that for landscape, so k is 1 there).
func fit(k := 1.0, max_w := 0.0) -> Vector2:
	var f := UiTheme.font(600)
	var fs := int(round(WORD_FONT * k))
	var sep := float(row.get_theme_constant("separation"))
	var n := row.get_child_count()
	while true:       # the words as long as the language needs; if the whole dock would pass `max_w`, every word steps down together
		var total := 2.0 * PAD + sep * float(maxi(n - 1, 0))
		for it: DockItem in row.get_children():
			total += maxf(TILE.x * k, f.get_string_size(tr(it.word.text), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 8.0)
		if max_w <= 0.0 or total <= max_w or fs <= FitText.MIN_SIZE: break
		fs -= 1
	for it: DockItem in row.get_children():
		var word := it.word
		word.add_theme_font_size_override("font_size", fs)
		var tw := f.get_string_size(tr(word.text), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		it.tile.custom_minimum_size = TILE * k
		var lh := f.get_height(fs)
		it.custom_minimum_size = Vector2(maxf(TILE.x * k, tw + 8.0), TILE.y * k + 3.0 + lh)
	reset_size()
	return get_combined_minimum_size()
