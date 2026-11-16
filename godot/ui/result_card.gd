class_name ResultCard
extends RefCounted
## The shareable end-of-match card (WP 0.6-C): a 1080x1920 portrait PNG built from Save.finish_match()'s summary plus a
## little match context, rendered offscreen and written to user://share/. The Results panel only shows a Share control
## when the provider-neutral `Share` autoload has a provider (docs/SHARE.md); nothing here imports a platform SDK.
##
## Headless test runs have the dummy renderer, so the SubViewport texture is unavailable: `render` then paints a
## deterministic flat placeholder at the same size, which keeps the API, file path and PNG checks testable.
## No gameplay RNG: the layout is fixed and the low-poly art is drawn from explicit points.

const WIDTH := 1080
const HEIGHT := 1920
const SIZE := Vector2i(WIDTH, HEIGHT)
const DIR := "user://share"
const PAD := 84

## Normalised card fields. `summary` is Save.finish_match()'s dictionary; `extra` adds context the save does not know:
## mode, arena, deaths, team, result (already localised) and look (world.gd `_my_look()`).
static func data(summary: Dictionary, extra: Dictionary = {}) -> Dictionary:
	var won := bool(extra.get("won", summary.get("won", false)))
	var mode := str(extra.get("mode", summary.get("mode", "")))
	var arena := str(extra.get("arena", summary.get("arena", summary.get("map", ""))))
	var result := str(extra.get("result", ""))
	if result == "":
		result = TranslationServer.translate("You win!" if won else "You lose")
	var look: Dictionary = {}
	var lk: Variant = extra.get("look", {})
	if lk is Dictionary:
		look = (lk as Dictionary).duplicate()
	return {
		"won": won,
		"kos": int(summary.get("kos", 0)),
		"deaths": int(extra.get("deaths", summary.get("deaths", 0))),
		"coins": int(summary.get("coins", 0)),
		"total": int(summary.get("total", 0)),
		"mode": mode,
		"arena": arena,
		"result": result,
		"look": look,
	}

## The localised "mode · arena" line ("" when neither is known).
static func place_line(d: Dictionary) -> String:
	var parts: Array = []
	if str(d.get("mode", "")) != "":
		parts.append(TranslationServer.translate(str(d["mode"])))
	if str(d.get("arena", "")) != "":
		parts.append(TranslationServer.translate(str(d["arena"])))
	return " · ".join(parts)

## The text handed to the share sheet beside the image. The card's own Labels auto-translate, so translate the result
## here too: world.gd passes the results panel's raw English text.
static func share_text(summary: Dictionary, extra: Dictionary = {}) -> String:
	var d := data(summary, extra)
	var stats := TranslationServer.translate("%s · %d K.O.s · %d deaths") % [place_line(d), int(d["kos"]), int(d["deaths"])]
	return "%s · %s · %s" % [TranslationServer.translate(str(d["result"])), stats, TranslationServer.translate("WOBBLERS ARENA")]

## A deterministic timestamped PNG path (UTC, so a test can pass a fixed time). `_free_path` adds a suffix only when the
## file already exists, so two shares in the same second do not overwrite each other.
static func path_for(summary: Dictionary, extra: Dictionary = {}, unix_time: int = -1) -> String:
	var d := data(summary, extra)
	var t := unix_time
	if t < 0:
		t = int(Time.get_unix_time_from_system())
	var dt := Time.get_datetime_dict_from_unix_time(t)
	var slug := _slug(str(d["mode"]))
	var suffix := "_" + slug if slug != "" else ""
	return "%s/wobblers%s_%04d%02d%02d-%02d%02d%02d.png" % [DIR, suffix,
		int(dt["year"]), int(dt["month"]), int(dt["day"]), int(dt["hour"]), int(dt["minute"]), int(dt["second"])]

## Build the card as a detached Control tree (tests inspect it; render puts it in a SubViewport).
static func build(summary: Dictionary, extra: Dictionary = {}) -> Control:
	var d := data(summary, extra)
	var root := Control.new()
	root.name = "ResultCard"
	root.size = Vector2(WIDTH, HEIGHT)
	root.custom_minimum_size = Vector2(WIDTH, HEIGHT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var art := CardArt.new()
	art.name = "CardArt"
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(art)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, PAD)
	root.add_child(margin)

	var body := VBoxContainer.new()
	body.name = "Body"
	body.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_theme_constant_override("separation", 34)
	margin.add_child(body)

	var logo_wrap := CenterContainer.new()
	logo_wrap.name = "LogoWrap"
	var logo := WobbleLogo.new()
	logo.name = "Logo"
	logo.lines = WobbleLogo.names(false)
	logo.font_size = 74
	logo.animate = false
	logo.custom_minimum_size = Vector2(0, 96)
	logo_wrap.add_child(logo)
	body.add_child(logo_wrap)

	body.add_child(_label("Kicker", TranslationServer.translate("Match result"), 30, UiTheme.MUTED))
	var result := _label("Result", str(d["result"]), 82, UiTheme.ACCENT)
	result.theme_type_variation = &"TitleLabel"
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(result)

	var place := place_line(d)
	if place != "":
		body.add_child(_label("ModeArena", place, 36, UiTheme.TEXT))

	var portrait_wrap := CenterContainer.new()
	portrait_wrap.name = "PortraitWrap"
	var portrait := WobblerPortrait.new()
	portrait.name = "Wobbler"
	portrait.look = d["look"]
	portrait.custom_minimum_size = Vector2(280, 320)
	portrait_wrap.add_child(portrait)
	body.add_child(portrait_wrap)

	var stats := HBoxContainer.new()
	stats.name = "Stats"
	stats.alignment = BoxContainer.ALIGNMENT_CENTER
	stats.add_theme_constant_override("separation", 18)
	for spec: Array in [
		["Kos", str(int(d["kos"])), "K.O.s", UiTheme.TEXT],
		["Deaths", str(int(d["deaths"])), "Deaths", UiTheme.TEXT],
		["Coins", "+%d" % int(d["coins"]), "Coins", UiTheme.ACCENT],
	]:
		stats.add_child(_stat_panel(str(spec[0]), str(spec[1]), str(spec[2]), spec[3] as Color))
	body.add_child(stats)

	body.add_child(_label("Total", TranslationServer.translate("%d coins in all") % int(d["total"]), 34, UiTheme.MUTED))
	return root

## The Share button, or null when no provider is registered. 60 canvas px = 44 pt at the touch UI scale (world.gd puts
## it beside Quit/Leave so small screens do not grow taller). The caller connects `pressed`.
static func share_control(share: Object) -> Button:
	if share == null or not share.has_method("has_provider"):
		return null
	if not bool(share.call("has_provider")):
		return null
	var b := Button.new()
	b.name = "ShareResult"
	b.text = TranslationServer.translate("Share card")
	b.custom_minimum_size = Vector2(0, 60)
	b.add_theme_font_size_override("font_size", 24)
	return b

## Render the card and write its PNG. Returns the saved path, or "" on failure. Headless: a painted placeholder of the
## same size (the dummy renderer has no viewport texture). Await it from a node in the tree.
static func render(host: Node, summary: Dictionary, extra: Dictionary = {}, unix_time: int = -1) -> String:
	if host == null or not host.is_inside_tree():
		return ""
	DirAccess.make_dir_recursive_absolute(DIR)
	var d := data(summary, extra)
	var path := _free_path(path_for(summary, extra, unix_time))
	var vp := SubViewport.new()
	vp.name = "ResultCardViewport"
	vp.size = SIZE
	vp.disable_3d = true
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	host.add_child(vp)
	var card := build(summary, extra)
	vp.add_child(card)
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.size = Vector2(SIZE)

	var img: Image = null
	if DisplayServer.get_name() == "headless":
		await host.get_tree().process_frame
	else:
		for i: int in 3:
			await host.get_tree().process_frame
		await RenderingServer.frame_post_draw
		var tex := vp.get_texture()
		if tex != null:
			img = tex.get_image()
	if img == null or img.is_empty():
		img = placeholder_image(d)
	var err := img.save_png(path)
	if err != OK:
		push_error("ResultCard: could not save %s (%s)" % [path, error_string(err)])
		path = ""
	vp.queue_free()
	await host.get_tree().process_frame
	return path

## Deterministic flat art for the headless (dummy renderer) path: same 1080x1920 size, theme colours, the low-poly bands
## and a chunky wobbler silhouette. No text: this is a fallback for tests/CI, not the player-facing render.
static func placeholder_image(d: Dictionary) -> Image:
	var img := Image.create(WIDTH, HEIGHT, false, Image.FORMAT_RGBA8)
	img.fill(UiTheme.PANEL_SOLID)
	var raised := Color(0.098, 0.247, 0.294, 1.0)
	img.fill_rect(Rect2i(0, 0, WIDTH, 330), raised)
	img.fill_rect(Rect2i(0, 330, WIDTH, 14), UiTheme.ACCENT)
	img.fill_rect(Rect2i(PAD, 430, WIDTH - PAD * 2, 170), Color(1, 1, 1, 0.08))
	img.fill_rect(Rect2i(PAD, 650, WIDTH - PAD * 2, 230), Color(0, 0, 0, 0.22))
	img.fill_rect(Rect2i(0, HEIGHT - 26, WIDTH, 26), raised)
	var box_w := (WIDTH - PAD * 2 - 36) / 3
	for i: int in 3:
		img.fill_rect(Rect2i(PAD + i * (box_w + 18), 930, box_w, 240), Color(0, 0, 0, 0.28))
		img.fill_rect(Rect2i(PAD + i * (box_w + 18), 930, box_w, 8), UiTheme.ACCENT if i == 2 else UiTheme.GOOD)
	img.fill_rect(Rect2i(PAD, 1250, WIDTH - PAD * 2, 10), Color(1, 1, 1, 0.18))
	var col := _look_colour(d.get("look", {}))
	var cx := WIDTH / 2
	img.fill_rect(Rect2i(cx - 100, 1360, 200, 300), col)
	img.fill_rect(Rect2i(cx - 70, 1300, 140, 140), col.lightened(0.1))
	img.fill_rect(Rect2i(cx - 40, 1340, 24, 24), UiTheme.INK)
	img.fill_rect(Rect2i(cx + 16, 1340, 24, 24), UiTheme.INK)
	return img

static func _stat_panel(n: String, value: String, caption: String, tint: Color) -> PanelContainer:
	var p := PanelContainer.new()
	p.name = n
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.custom_minimum_size = Vector2(240, 170)
	p.add_theme_stylebox_override("panel", UiTheme.box(Color(0, 0, 0, 0.26), 20, Color(1, 1, 1, 0.12), 2, 0))
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 2)
	p.add_child(box)
	var v := _label(n + "Value", value, 58, tint)
	v.add_theme_font_override("font", UiTheme.font(700))
	box.add_child(v)
	box.add_child(_label(n + "Caption", TranslationServer.translate(caption), 26, UiTheme.MUTED))
	return p

static func _label(n: String, text: String, font_size: int, col: Color) -> Label:
	var l := Label.new()
	l.name = n
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", col)
	return l

static func _slug(s: String) -> String:
	var out := ""
	for ch: String in s.to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
		elif out != "" and not out.ends_with("_"):
			out += "_"
	return out.trim_suffix("_")

static func _free_path(base: String) -> String:
	if not FileAccess.file_exists(base):
		return base
	var stem := base.get_basename()
	var i := 2
	while FileAccess.file_exists("%s_%d.png" % [stem, i]):
		i += 1
	return "%s_%d.png" % [stem, i]

static func _look_colour(look: Variant) -> Color:
	var v: Variant = (look as Dictionary).get("color", 0x39b5a8) if look is Dictionary else 0x39b5a8
	if v is Color:
		return v
	var n := int(v)
	return Color8((n >> 16) & 0xff, (n >> 8) & 0xff, n & 0xff)

## The card background: flat teal with a few large low-poly facets (no textures, no RNG).
class CardArt extends Control:
	func _draw() -> void:
		var w := size.x
		var h := size.y
		draw_rect(Rect2(Vector2.ZERO, size), UiTheme.PANEL_SOLID)
		var hi := Color(0.098, 0.247, 0.294, 1.0)
		var lo := Color(0.047, 0.133, 0.165, 1.0)
		draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w * 0.64, 0), Vector2(w * 0.33, h * 0.30), Vector2(0, h * 0.38)]), hi)
		draw_colored_polygon(PackedVector2Array([Vector2(w, 0), Vector2(w, h * 0.46), Vector2(w * 0.62, h * 0.22)]), hi.darkened(0.12))
		draw_colored_polygon(PackedVector2Array([Vector2(0, h), Vector2(w * 0.44, h * 0.68), Vector2(w, h)]), lo)
		draw_colored_polygon(PackedVector2Array([Vector2(0, h * 0.38), Vector2(w * 0.33, h * 0.30), Vector2(w * 0.62, h * 0.22), Vector2(w, h * 0.46), Vector2(w, h * 0.54), Vector2(0, h * 0.86)]), Color(0.071, 0.196, 0.235, 1.0))
		draw_rect(Rect2(0, 0, w, 12), UiTheme.ACCENT)
		draw_rect(Rect2(0, h - 12, w, 12), UiTheme.ACCENT)

## A cheap flat wobbler portrait from the look's body colour (the outfit colour is already resolved by world.gd).
class WobblerPortrait extends Control:
	var look: Dictionary = {}

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var col := ResultCard._look_colour(look)
		var dark := col.darkened(0.28)
		draw_colored_polygon(_ellipse(Vector2(w * 0.5, h * 0.93), w * 0.30, h * 0.045, 20), Color(0, 0, 0, 0.30))
		draw_rect(Rect2(w * 0.31, h * 0.70, w * 0.14, h * 0.20), dark)
		draw_rect(Rect2(w * 0.55, h * 0.70, w * 0.14, h * 0.20), dark.darkened(0.15))
		draw_colored_polygon(PackedVector2Array([
			Vector2(w * 0.26, h * 0.39), Vector2(w * 0.50, h * 0.34), Vector2(w * 0.50, h * 0.79), Vector2(w * 0.24, h * 0.73)]), col)
		draw_colored_polygon(PackedVector2Array([
			Vector2(w * 0.50, h * 0.34), Vector2(w * 0.74, h * 0.39), Vector2(w * 0.76, h * 0.73), Vector2(w * 0.50, h * 0.79)]), col.darkened(0.10))
		draw_circle(Vector2(w * 0.50, h * 0.27), w * 0.20, col.lightened(0.10))
		draw_circle(Vector2(w * 0.43, h * 0.26), w * 0.035, UiTheme.INK)
		draw_circle(Vector2(w * 0.57, h * 0.26), w * 0.035, UiTheme.INK)
		if str(look.get("hat", "none")) != "none":
			draw_rect(Rect2(w * 0.30, h * 0.15, w * 0.40, h * 0.035), UiTheme.ACCENT)
			draw_colored_polygon(PackedVector2Array([
				Vector2(w * 0.36, h * 0.15), Vector2(w * 0.50, h * 0.05), Vector2(w * 0.64, h * 0.15)]), UiTheme.ORANGE)

	func _ellipse(c: Vector2, rx: float, ry: float, n: int) -> PackedVector2Array:
		var pts := PackedVector2Array()
		for i: int in n:
			var a := TAU * float(i) / float(n)
			pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
		return pts
