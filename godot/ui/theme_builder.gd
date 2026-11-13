class_name UiTheme
extends SceneTree
## The one UI look (dark teal panels, warm yellow accent, white heavy rounded type, 2 px borders, rounded corners,
## soft shadows), built in code so it stays reviewable. Writes res://ui/theme.tres, which project.godot sets as the
## project theme (gui/theme/custom), so every Control gets it. Rebuild after changing this file:
##   godot --headless --path godot --script res://ui/theme_builder.gd
## Type variations: PrimaryButton (big yellow), ChipPanel (small pill), HudPanel (in-match panel), HudLabel
## (outlined text over the 3D view), TitleLabel, MutedLabel.

const PATH := "res://ui/theme.tres"
const FONT_PATH := "res://ui/fonts/Fredoka-Variable.ttf"

const PANEL := Color(0.0627, 0.1686, 0.2078, 0.85)       ## #102b35 at 0.85
const PANEL_SOLID := Color(0.0627, 0.1686, 0.2078, 1.0)
const PANEL_HI := Color(0.098, 0.247, 0.294, 0.92)       ## raised teal (buttons)
const PANEL_EDGE := Color(1, 1, 1, 0.16)
const ACCENT := Color(1.0, 0.812, 0.353)                 ## #ffcf5a
const ACCENT_DARK := Color(0.85, 0.6, 0.16)
const ORANGE := Color(1.0, 0.6, 0.2)
const INK := Color(0.0627, 0.1686, 0.2078)               ## dark text on yellow
const TEXT := Color(1, 1, 1)
const MUTED := Color(0.72, 0.82, 0.85)
const GOOD := Color(0.294, 0.82, 0.541)                  ## #4bd18a (web health)
const WARN := Color(0.961, 0.725, 0.259)                 ## #f5b942
const BAD := Color(0.937, 0.325, 0.314)                  ## #ef5350
const SHADOW := Color(0, 0, 0, 0.32)
const RADIUS := 14
const BORDER := 2
## Spacing scale (canvas px; the layouts use these, never ad-hoc numbers): 4 hairline, 8 inside a control group, 12 between
## controls (>= 8 pt at the 44 pt UI scale: the gap tests/ui_layout_test.gd demands), 16 between groups, 24 between sections.
const SP_1 := 4
const SP_2 := 8
const SP_3 := 12
const SP_4 := 16
const SP_5 := 24
const MIN_FONT := 14           ## smallest label font (canvas px, about 10 pt on an iPhone); the layout test enforces it
const MIN_GAP := 11.0          ## smallest gap between two controls (canvas px at the 44 pt scale = 8 pt)

func _initialize() -> void:
	var t := build()
	var err := ResourceSaver.save(t, PATH)
	print("THEME ", PATH, " ", "ok" if err == OK else "error %d" % err)
	quit(0 if err == OK else 1)

## Heavy rounded font (Fredoka, SIL OFL: ui/fonts/OFL.txt) at a variable-font weight (300..700).
static func font(weight: int = 600) -> Font:
	var base: FontFile = load(FONT_PATH)
	var f := FontVariation.new()
	f.base_font = base
	f.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	return f

static func box(bg: Color, radius: int = RADIUS, border: Color = PANEL_EDGE, bw: int = BORDER, shadow := 6, lip := 0, lip_col := Color.TRANSPARENT) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.border_color = border
	s.set_border_width_all(bw)
	if lip > 0:
		s.border_width_bottom = lip
		if lip_col.a > 0.0:
			s.border_color = lip_col
	s.shadow_color = SHADOW
	s.shadow_size = shadow
	s.shadow_offset = Vector2(0, 3)
	s.anti_aliasing = true
	s.corner_detail = 10
	s.content_margin_left = 18; s.content_margin_right = 18
	s.content_margin_top = 10; s.content_margin_bottom = 10
	return s

## Normal / hover / pressed / disabled / focus boxes for one button colour. The thick darker bottom edge is the
## playful "lip" of the web buttons; pressed squashes it and moves the text down.
static func _button_boxes(t: Theme, type: String, bg: Color, edge: Color, text: Color, text_dark := false) -> void:
	var n := box(bg, RADIUS, edge, BORDER, 6, 6)
	var h := box(bg.lightened(0.1), RADIUS, edge.lightened(0.15), BORDER, 8, 6)
	var p := box(bg.darkened(0.08), RADIUS, edge, BORDER, 2, 2)
	p.content_margin_top += 4; p.shadow_offset = Vector2(0, 1)
	var d := box(Color(bg.r, bg.g, bg.b, bg.a * 0.45).lerp(Color(0.3, 0.35, 0.38, 0.6), 0.6), RADIUS, Color(1, 1, 1, 0.08), BORDER, 0, 4)
	var f := box(Color.TRANSPARENT, RADIUS + 3, ACCENT if not text_dark else Color.WHITE, 3, 0)
	f.draw_center = false
	f.expand_margin_left = 3; f.expand_margin_right = 3; f.expand_margin_top = 3; f.expand_margin_bottom = 3
	t.set_stylebox("normal", type, n)
	t.set_stylebox("hover", type, h)
	t.set_stylebox("pressed", type, p)
	t.set_stylebox("hover_pressed", type, p)
	t.set_stylebox("disabled", type, d)
	t.set_stylebox("focus", type, f)
	t.set_color("font_color", type, text)
	t.set_color("font_hover_color", type, text)
	t.set_color("font_pressed_color", type, text)
	t.set_color("font_hover_pressed_color", type, text)
	t.set_color("font_focus_color", type, text)
	t.set_color("font_disabled_color", type, Color(text.r, text.g, text.b, 0.45))
	t.set_color("icon_normal_color", type, text)
	t.set_color("icon_hover_color", type, text)
	t.set_color("icon_pressed_color", type, text)
	t.set_color("icon_focus_color", type, text)

static func build() -> Theme:
	var t := Theme.new()
	t.default_font = font(600)
	t.default_font_size = 22
	var heavy := font(700)

	# panels
	t.set_stylebox("panel", "PanelContainer", box(PANEL, 18))
	t.set_stylebox("panel", "Panel", box(PANEL, 18))
	t.set_type_variation("HudPanel", "PanelContainer")
	var hp := box(Color(PANEL.r, PANEL.g, PANEL.b, 0.78), 14, Color(1, 1, 1, 0.14), BORDER, 5)
	hp.content_margin_left = 14; hp.content_margin_right = 14; hp.content_margin_top = 6; hp.content_margin_bottom = 6
	t.set_stylebox("panel", "HudPanel", hp)
	t.set_type_variation("ChipPanel", "PanelContainer")
	var chip := box(Color(PANEL.r, PANEL.g, PANEL.b, 0.9), 99, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.55), BORDER, 4)
	chip.content_margin_left = 14; chip.content_margin_right = 16; chip.content_margin_top = 5; chip.content_margin_bottom = 5
	t.set_stylebox("panel", "ChipPanel", chip)

	# labels
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.3))
	t.set_constant("shadow_offset_x", "Label", 0)
	t.set_constant("shadow_offset_y", "Label", 2)
	t.set_type_variation("HudLabel", "Label")
	t.set_font("font", "HudLabel", heavy)
	t.set_color("font_outline_color", "HudLabel", Color(INK.r, INK.g, INK.b, 0.9))
	t.set_constant("outline_size", "HudLabel", 6)
	t.set_type_variation("TitleLabel", "Label")
	t.set_font("font", "TitleLabel", heavy)
	t.set_font_size("font_size", "TitleLabel", 40)
	t.set_type_variation("MutedLabel", "Label")
	t.set_color("font_color", "MutedLabel", MUTED)
	t.set_font_size("font_size", "MutedLabel", 18)

	# buttons
	_button_boxes(t, "Button", PANEL_HI, Color(1, 1, 1, 0.2), TEXT)
	t.set_font("font", "Button", heavy)
	t.set_font_size("font_size", "Button", 24)
	t.set_type_variation("PrimaryButton", "Button")
	_button_boxes(t, "PrimaryButton", ACCENT, ACCENT_DARK, INK, true)
	t.set_font_size("font_size", "PrimaryButton", 34)
	_button_boxes(t, "OptionButton", PANEL_HI, Color(1, 1, 1, 0.2), TEXT)
	t.set_font("font", "OptionButton", heavy)
	t.set_icon("arrow", "OptionButton", _arrow_icon())
	t.set_constant("arrow_margin", "OptionButton", 14)
	_button_boxes(t, "CheckButton", Color(PANEL_HI.r, PANEL_HI.g, PANEL_HI.b, 0.0), Color(1, 1, 1, 0.0), TEXT)
	for k in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var sb: StyleBoxFlat = t.get_stylebox(k, "CheckButton")
		sb.shadow_size = 0
	t.set_icon("checked", "CheckButton", _switch_icon(true))
	t.set_icon("unchecked", "CheckButton", _switch_icon(false))
	t.set_icon("checked_disabled", "CheckButton", _switch_icon(true))
	t.set_icon("unchecked_disabled", "CheckButton", _switch_icon(false))
	t.set_constant("h_separation", "CheckButton", 14)

	# tab pills (title: Offline / Play online)
	t.set_type_variation("TabButton", "Button")
	_button_boxes(t, "TabButton", Color(PANEL_HI.r, PANEL_HI.g, PANEL_HI.b, 0.55), Color(1, 1, 1, 0.14), MUTED)
	for k in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var sb: StyleBoxFlat = (t.get_stylebox(k, "TabButton") as StyleBoxFlat).duplicate()
		sb.set_corner_radius_all(99)
		sb.border_width_bottom = BORDER
		sb.shadow_size = 0
		sb.content_margin_top = 6; sb.content_margin_bottom = 6
		if k == "pressed" or k == "hover_pressed":
			sb.bg_color = ACCENT; sb.border_color = ACCENT_DARK
		t.set_stylebox(k, "TabButton", sb)
	t.set_color("font_pressed_color", "TabButton", INK)
	t.set_color("font_hover_pressed_color", "TabButton", INK)
	t.set_color("font_hover_color", "TabButton", TEXT)
	t.set_font_size("font_size", "TabButton", 19)

	# text fields
	var le := box(Color(0.03, 0.1, 0.12, 0.9), 12, Color(1, 1, 1, 0.18), BORDER, 0)
	le.content_margin_left = 12; le.content_margin_right = 12; le.content_margin_top = 6; le.content_margin_bottom = 6
	var lf: StyleBoxFlat = le.duplicate()
	lf.border_color = ACCENT
	var lr: StyleBoxFlat = le.duplicate()
	lr.bg_color = Color(0.03, 0.1, 0.12, 0.5)
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus", "LineEdit", lf)
	t.set_stylebox("read_only", "LineEdit", lr)
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", Color(MUTED.r, MUTED.g, MUTED.b, 0.55))
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_color("selection_color", "LineEdit", Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.4))

	# popups (OptionButton lists)
	var pm := box(PANEL_SOLID, 14, Color(1, 1, 1, 0.22), BORDER, 10)
	pm.content_margin_top = 8; pm.content_margin_bottom = 8; pm.content_margin_left = 8; pm.content_margin_right = 8
	t.set_stylebox("panel", "PopupMenu", pm)
	var ph := box(ACCENT, 10, ACCENT, 0, 0)
	t.set_stylebox("hover", "PopupMenu", ph)
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", INK)
	t.set_font("font", "PopupMenu", heavy)
	t.set_font_size("font_size", "PopupMenu", 22)
	t.set_constant("v_separation", "PopupMenu", 12)
	t.set_constant("item_start_padding", "PopupMenu", 12)
	t.set_constant("item_end_padding", "PopupMenu", 12)
	var empty := StyleBoxEmpty.new()
	t.set_icon("radio_checked", "PopupMenu", _dot_icon(true))
	t.set_icon("radio_unchecked", "PopupMenu", _dot_icon(false))
	t.set_stylebox("panel", "PopupPanel", pm)
	t.set_stylebox("embedded_border", "Window", empty)
	t.set_stylebox("embedded_unfocused_border", "Window", empty)

	# progress bars (HUD fallback)
	t.set_stylebox("background", "ProgressBar", box(Color(0, 0, 0, 0.45), 8, Color(1, 1, 1, 0.15), BORDER, 0))
	t.set_stylebox("fill", "ProgressBar", box(GOOD, 8, Color(0, 0, 0, 0), 0, 0))
	# tooltips
	t.set_stylebox("panel", "TooltipPanel", box(PANEL_SOLID, 10))
	t.set_color("font_color", "TooltipLabel", TEXT)
	return t

# ---------- small rasterised icons (no image files needed) ----------

## Signed-distance coverage for an anti-aliased shape in an Image.
static func _cov(d: float) -> float:
	return clampf(0.5 - d, 0.0, 1.0)

static func _blend(img: Image, x: int, y: int, c: Color, a: float) -> void:
	if a <= 0.0: return
	var o := img.get_pixel(x, y)
	var na := a * c.a
	var outa := na + o.a * (1.0 - na)
	if outa <= 0.0: return
	var rgb := (Color(c.r, c.g, c.b) * na + Color(o.r, o.g, o.b) * o.a * (1.0 - na)) / outa
	img.set_pixel(x, y, Color(rgb.r, rgb.g, rgb.b, outa))

static func _pill(img: Image, r: Rect2, c: Color) -> void:
	var rad := r.size.y / 2.0
	for y in img.get_height():
		for x in img.get_width():
			var p := Vector2(x + 0.5, y + 0.5)
			var cx := clampf(p.x, r.position.x + rad, r.end.x - rad)
			var d := p.distance_to(Vector2(cx, r.position.y + rad)) - rad
			_blend(img, x, y, c, _cov(d))

static func _disc(img: Image, ctr: Vector2, rad: float, c: Color) -> void:
	for y in img.get_height():
		for x in img.get_width():
			_blend(img, x, y, c, _cov(Vector2(x + 0.5, y + 0.5).distance_to(ctr) - rad))

static func _switch_icon(on: bool) -> ImageTexture:
	var img := Image.create(56, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	if on:
		_pill(img, Rect2(1, 1, 54, 30), ACCENT_DARK)
		_pill(img, Rect2(3, 3, 50, 26), ACCENT)
		_disc(img, Vector2(40, 16), 10.5, Color.WHITE)
	else:
		_pill(img, Rect2(1, 1, 54, 30), Color(1, 1, 1, 0.35))
		_pill(img, Rect2(3, 3, 50, 26), Color(0.04, 0.12, 0.15, 1))
		_disc(img, Vector2(16, 16), 10.5, Color(0.75, 0.83, 0.86))
	return ImageTexture.create_from_image(img)

static func _dot_icon(on: bool) -> ImageTexture:
	var img := Image.create(20, 20, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	_disc(img, Vector2(10, 10), 8.0, Color(1, 1, 1, 0.5))
	_disc(img, Vector2(10, 10), 6.0, PANEL_SOLID)
	if on:
		_disc(img, Vector2(10, 10), 4.5, ACCENT)
	return ImageTexture.create_from_image(img)

static func _arrow_icon() -> ImageTexture:
	var img := Image.create(20, 14, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	# a chunky rounded chevron: distance to two segments
	var a := Vector2(4, 4); var b := Vector2(10, 10); var c := Vector2(16, 4)
	for y in img.get_height():
		for x in img.get_width():
			var p := Vector2(x + 0.5, y + 0.5)
			var d := minf(_seg(p, a, b), _seg(p, b, c)) - 2.0
			_blend(img, x, y, Color.WHITE, _cov(d))
	return ImageTexture.create_from_image(img)

static func _seg(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)
