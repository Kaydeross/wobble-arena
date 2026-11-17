class_name PackLanding
extends Control
## The landing page of a DLC pack: the hero of the pack hub (dlc/construction/construction_hub.gd, which serves every pack). Two parts:
##   * the BACKDROP (ui/pack_landing_scene.gd) behind the whole page: the pack's colours, and for Construction (which keeps its own
##     look) a light crane overlay;
##   * the HERO BAND between the header and the cards: the pack's badge and title lockup (`headline`, uppercased, and the tagline),
##     the stage slot, the weapon's name and role line, a top-down arena thumbnail (ui/pack_landing_arena.gd, drawn once from the
##     pack's generator) and three features. Kitchen, Xmas and Australia fill the band with a real 3D SET (ui/pack_landing_set.gd,
##     rendered by the ONE SubViewport ui/pack_landing_stage.gd, like the title's Construction showcase): a kitchen with the Wobbler
##     behind the prep counter, a snow globe with the Wobbler inside, a desert suburb with a kangaroo. The dressed Wobbler and the
##     pack's weapon on its turntable (the real WeaponModels.build(id); tap the stage or wait to see the next) stand in the stage
##     slot, the scenery runs on behind the texts (`scrim` keeps them readable). Construction keeps the small plain stage in its slot.
## The band takes only the space the cards leave over (its minimum height is 0, so the hub's layout and its tests do not change) and
## shows what fits: under MIN_H nothing, short bands (a phone in landscape) the lockup, the stage, the caption and the features, taller
## ones also the arena. The data is data/extra/<pack>/landing.json (all text is an English tr() key).
## Performance budget: at most ONE SubViewport (the stage, reused for every pack and weapon, as big as the band, no MSAA, rendered
## only while the band is on screen), PackLandingScene.PARTICLE_CAP particles for the whole page, PackLandingSet.MESH_CAP mesh
## instances, no per-frame allocation, the arena drawn once, everything paused while the hub is hidden or covered. Lowest graphics
## tier (Tier.q() == 0): no particles, the stage renders once per change. Headless: no stage, no 3D, no particles (layout nodes
## stay, so tests can read the texts and buttons); PackLanding.force_fx builds them anyway (tests).

const FILE := "landing.json"
const MIN_H := 74.0
const MINI_H := 40.0                   ## under MIN_H and from here: a single row (badge, title, tagline)
const FONT_MIN := 14                   ## UiTheme.MIN_FONT: a piece that cannot be read at this size is hidden, never shrunk below it
const TOUCH := 62.0                    ## the tap target of the stage: the UI's own touch size in canvas px (ConstructionHub.TOUCH)
const MIN_W := 360.0
const CYCLE_S := 3.6
const MAX_CONTENT_H := 320.0           ## a tall band (tablet) keeps its content this high, centred
const TEXT := Color("#f6f1e6")

static var force_fx := false           ## tests: build the stage and the particles in headless too
static var _cache: Dictionary = {}

var pack_id := ""
var data: Dictionary = {}
var scene: PackLandingScene
var stage: PackLandingStage
var arena: PackLandingArena
var weapons: Array[String] = []
var wi := 0
var accent := Color("#ffc21a")
var glass: Panel
var badge: PackBadge
var headline: Label
var tagline: Label
var view_clip: Panel                   ## the 3D set's picture, clipped to the band's rounded corners (under the glass frame)
var view: TextureRect
var scrim: Control                     ## darkens the set behind the texts, left and right of the stage slot
var stage_tex: TextureRect             ## the stage slot: the plain stage's picture (Construction), or just the place the 3D set's subject shows
var stage_btn: Button
var w_name: Label
var w_role: Label
var arena_name: Label
var feats: Array[Label] = []
var dots: Control
var content: Array[Control] = []
var shown := false                     ## the full content fits and is on screen
var mini := false                      ## the band is only tall enough for the badge, the title and the tagline in one row
var _auto := 0.0
var _vis := false
var _arena_due := false
var _arena_for := ""
var _fill := Color(0, 0, 0, 0)
var _cover: Control          ## a sheet that can cover the hub (the code sheet): everything pauses while it is up
var _want := {}
var _settling := false

func _init() -> void:
	name = "Landing"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = SIZE_EXPAND_FILL
	size_flags_horizontal = SIZE_EXPAND_FILL
	custom_minimum_size = Vector2.ZERO
	clip_contents = true

# ---------------- data ----------------

static func fx_on() -> bool:
	return force_fx or DisplayServer.get_name() != "headless"

## data/extra/<pack>/landing.json ({} = none), cached per pack folder.
static func load_data(id: String) -> Dictionary:
	var pk: Dictionary = Content.pack(id)
	if pk.is_empty(): return {}
	var path := str(pk.get("dir", "res://data/extra/" + id)).path_join(FILE)
	if _cache.has(path): return _cache[path]
	var out := {}
	if FileAccess.file_exists(path):
		var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if v is Dictionary: out = v
	_cache[path] = out
	return out

static func reset_cache() -> void:
	_cache.clear()

static func pal(d: Dictionary) -> Dictionary:
	var out := {}
	var p: Dictionary = d.get("palette", {})
	for k: String in p: out[k] = Color(str(p[k]))
	return out

## The pack's weapons in showcase order (only ones the build has).
static func weapon_ids(id: String) -> Array[String]:
	var st: Resource = PackRegistry.style(id)
	var out: Array[String] = []
	if st != null:
		var all: Array[String] = st.call("real_weapons", Content.weapons)
		out = all
	return out

## The three strings of a pack's landing that every language must have (tests).
static func texts_of(d: Dictionary) -> Array:
	var out: Array = [str(d.get("headline", "")), str(d.get("tagline", ""))]
	out.append_array(d.get("features", []))
	for k: String in (d.get("weapon_roles", {}) as Dictionary): out.append(str((d["weapon_roles"] as Dictionary)[k]))
	return out

## The card colour the pack asks for (alpha 0 = keep the hub's own; Construction).
func card_fill() -> Color:
	return _fill

func headline_text() -> String:
	return tr(str(data.get("headline", PackRegistry.display_name(pack_id)))).to_upper()

func current_weapon() -> String:
	return weapons[wi] if wi >= 0 and wi < weapons.size() else ""

func stage_count() -> int:
	return 1 if stage != null else 0

func particle_total() -> int:
	return (scene.particle_total() if scene != null else 0) + (stage.particle_total() if stage != null else 0)

## The band shows a 3D set (kitchen, xmas, australia), not the plain stage.
func has_set() -> bool:
	return stage != null and stage.set3d != null

# ---------------- building ----------------

## Called once by the hub: the backdrop goes behind the page's column, the band into the column under the header.
func attach(hub: Control) -> void:
	scene = PackLandingScene.new()
	_cover = hub.get("code_sheet") as Control
	hub.add_child(scene)
	hub.move_child(scene, 1)                     # over the opaque Bg, under Safe
	var col: Control = hub.get("col")
	col.add_child(self)
	col.move_child(self, 1)
	var mv: Control = hub.get("main_view")
	mv.size_flags_vertical = SIZE_FILL           # the band takes the spare height, the cards keep their own
	mv.visibility_changed.connect(func() -> void: visible = mv.visible)
	_build()
	resized.connect(_layout)

func _lab(n: String, bold: bool) -> Label:
	var l := Label.new()
	l.name = n
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_color", TEXT)
	l.add_theme_font_override("font", UiTheme.font(700 if bold else 600))
	l.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.03, 0.8))
	l.add_theme_constant_override("outline_size", 4)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(l)
	content.append(l)
	return l

func _build() -> void:
	view_clip = Panel.new()
	view_clip.name = "Set3D"
	view_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view_clip.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	var vs := StyleBoxFlat.new()
	vs.bg_color = Color.WHITE
	vs.set_corner_radius_all(UiTheme.RADIUS)
	vs.anti_aliasing = true
	view_clip.add_theme_stylebox_override("panel", vs)
	view_clip.visible = false
	add_child(view_clip)
	view = TextureRect.new()
	view.name = "View"
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_SCALE
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view_clip.add_child(view)
	scrim = Control.new()
	scrim.name = "Scrim"
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.draw.connect(_draw_scrim)
	view_clip.add_child(scrim)
	glass = Panel.new()
	glass.name = "Glass"
	glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glass)
	content.append(glass)
	badge = PackBadge.new("", accent, 44.0)
	badge.name = "Badge"
	add_child(badge)
	content.append(badge)
	headline = _lab("Headline", true)
	headline.add_theme_constant_override("outline_size", 8)
	tagline = _lab("Tagline", false)
	tagline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stage_tex = TextureRect.new()
	stage_tex.name = "Stage"
	stage_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stage_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(stage_tex)
	content.append(stage_tex)
	stage_btn = Button.new()
	stage_btn.name = "NextWeapon"
	stage_btn.flat = true
	stage_btn.focus_mode = Control.FOCUS_NONE
	stage_btn.text = ""
	stage_btn.tooltip_text = "Next weapon"
	stage_btn.set("accessibility_name", tr("Next weapon"))
	stage_btn.pressed.connect(func() -> void: cycle(1))
	add_child(stage_btn)
	content.append(stage_btn)
	w_name = _lab("WeaponName", true)
	w_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	w_role = _lab("WeaponRole", false)
	w_role.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	w_role.add_theme_color_override("font_color", Color(TEXT.r, TEXT.g, TEXT.b, 0.82))
	arena = PackLandingArena.new()
	add_child(arena)
	content.append(arena)
	arena_name = _lab("ArenaName", false)
	arena_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	arena_name.add_theme_color_override("font_color", Color(TEXT.r, TEXT.g, TEXT.b, 0.82))
	for i in 3:
		var f := _lab("Feature%d" % (i + 1), false)
		f.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		feats.append(f)
	dots = Control.new()
	dots.name = "Dots"
	dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dots.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dots.draw.connect(_draw_dots)
	add_child(dots)
	content.append(dots)
	set_process(true)

## Fills the page for pack `id`: backdrop, texts, the wobbler and the weapon list.
func set_pack(id: String) -> void:
	pack_id = id
	data = load_data(id)
	weapons = weapon_ids(id)
	wi = 0
	_auto = 0.0
	accent = PackRegistry.accent(id)
	var p := pal(data)
	_fill = Color(0, 0, 0, 0)
	if p.has("card") and not bool(data.get("overlay", false)):
		_fill = p["card"]
		_fill.a = 0.72
	var tier := Tier.q()
	var fx := fx_on()
	var kind := str(data.get("backdrop", id))
	scene.setup(kind, p, fx and tier > 0, fx and tier > 0)
	headline.add_theme_color_override("font_color", p.get("ink", TEXT) if p.has("ink") else TEXT)
	headline.add_theme_color_override("font_outline_color", Color(p.get("glow", accent)).darkened(0.62))
	badge.kind = PackRegistry.badge(id)
	badge.col = accent
	badge.queue_redraw()
	var gs := StyleBoxFlat.new()
	gs.bg_color = Color(0.02, 0.03, 0.04, 0.0 if fx and PackLandingSet.has(kind) else 0.24)   # a 3D set fills the band: the scrim does the dimming
	gs.border_color = Color(accent.r, accent.g, accent.b, 0.8)
	gs.set_border_width_all(2)
	gs.set_corner_radius_all(UiTheme.RADIUS)
	gs.anti_aliasing = true
	glass.add_theme_stylebox_override("panel", gs)
	if fx:
		_ensure_stage(tier)
		stage.set_look(data.get("wobbler", {}))
		stage.set_scene(kind, p, headline_text(), tier > 0)
		var on_set := stage.set3d != null
		stage_tex.texture = null if on_set else stage.get_texture()
		view.texture = stage.get_texture() if on_set else null
	if arena != null:
		arena.frame_col = Color(accent.r, accent.g, accent.b, 0.9)
		arena.set_map({})
	_arena_due = fx_on()
	_arena_for = ""
	_texts()
	_show_weapon(0)
	_layout()

func _ensure_stage(tier: int) -> void:
	if stage == null:
		stage = PackLandingStage.new()
		add_child(stage)
	stage.spin = tier > 0

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and headline != null and not data.is_empty():
		_texts()
		if has_set(): stage.set_scene(stage.set3d.kind, pal(data), headline_text(), stage.set3d.with_fx)   # the name on the snow globe
		_layout()

## The texts in the language in use.
func _texts() -> void:
	headline.text = headline_text()
	tagline.text = tr(str(data.get("tagline", "")))
	var fl: Array = data.get("features", [])
	for i in 3:
		feats[i].text = tr(str(fl[i])) if i < fl.size() else ""
	_weapon_texts()
	var an := ""
	var st: Resource = PackRegistry.style(pack_id)
	if st != null:
		var m: Variant = (Content.maps as Dictionary).get(str(st.get("arena_id")), {})
		if m is Dictionary: an = tr(str((m as Dictionary).get("name", "")))
	arena_name.text = an
	stage_btn.tooltip_text = tr("Next weapon")

func _weapon_texts() -> void:
	var id := current_weapon()
	if id == "":
		w_name.text = ""
		w_role.text = ""
		return
	var wd: Dictionary = (Content.weapons as Dictionary).get(id, {})
	w_name.text = tr(str(wd.get("name", id)))
	var roles: Dictionary = data.get("weapon_roles", {})
	w_role.text = tr(str(roles.get(id, ""))) if roles.has(id) else ""

# ---------------- the weapon showcase ----------------

## Next (1) or previous (-1) weapon.
func cycle(step: int) -> void:
	if weapons.is_empty(): return
	_show_weapon(posmod(wi + step, weapons.size()))
	if stage != null and step != 0: stage.shake()
	_auto = 0.0

func _show_weapon(i: int) -> void:
	if weapons.is_empty(): return
	wi = clampi(i, 0, weapons.size() - 1)
	if stage != null: stage.show_weapon(weapons[wi])
	_weapon_texts()
	if headline != null and shown: _layout_caption()

# ---------------- layout ----------------

func _draw_dots() -> void:
	if not shown: return
	for f: Label in feats:
		if f.visible and f.text != "":
			dots.draw_circle(Vector2(f.position.x - 9.0, f.position.y + f.size.y * 0.5), 3.5, accent)

## The dimming over a 3D set, left and right of the stage slot (the subject stays clear), fading out towards it.
func _draw_scrim() -> void:
	if not has_set() or not shown: return
	var h := scrim.size.y
	var x0 := stage_tex.position.x - view_clip.position.x
	var x1 := x0 + stage_tex.size.x
	var fade := 70.0
	var c := Color(0.03, 0.035, 0.05, 0.5)
	var c0 := Color(c.r, c.g, c.b, 0.0)
	scrim.draw_rect(Rect2(0, 0, maxf(x0 - fade, 0.0), h), c)
	_quad[0] = Vector2(x0 - fade, 0); _quad[1] = Vector2(x0 + 16.0, 0); _quad[2] = Vector2(x0 + 16.0, h); _quad[3] = Vector2(x0 - fade, h)
	_qcol[0] = c; _qcol[1] = c0; _qcol[2] = c0; _qcol[3] = c
	scrim.draw_polygon(_quad, _qcol)
	_quad[0] = Vector2(x1 - 16.0, 0); _quad[1] = Vector2(x1 + fade, 0); _quad[2] = Vector2(x1 + fade, h); _quad[3] = Vector2(x1 - 16.0, h)
	_qcol[0] = c0; _qcol[1] = c; _qcol[2] = c; _qcol[3] = c0
	scrim.draw_polygon(_quad, _qcol)
	scrim.draw_rect(Rect2(x1 + fade, 0, maxf(scrim.size.x - x1 - fade, 0.0), h), c)

var _quad := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var _qcol := PackedColorArray([Color.BLACK, Color.BLACK, Color.BLACK, Color.BLACK])

## Sets a control's size and remembers it: a control cannot be made smaller than the minimum size it had a moment ago (the cache
## updates after the frame), so _settle() applies the remembered sizes once more after it.
func _put_size(c: Control, v: Vector2) -> void:
	_want[c] = v
	c.size = v
	if not _settling:
		_settling = true
		_settle.call_deferred()

func _settle() -> void:
	_settling = false
	for c: Control in _want:
		if is_instance_valid(c) and c.size != _want[c]: c.size = _want[c]

func _fit(l: Label, text: String, max_fs: int, w: float, min_fs: int) -> void:
	l.text = text
	var fs := FitText.size_for(l.get_theme_font("font"), l.tr(text), max_fs, w, min_fs)
	l.add_theme_font_size_override("font_size", fs)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF

## A wrapped label at `w` whose lines fit `max_h` (the font steps down to min_fs); its box is as tall as its lines.
func _fit_wrap(l: Label, text: String, max_fs: int, w: float, max_h: float, min_fs: int) -> float:
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var fs := maxi(max_fs, min_fs)
	var need := 0.0
	while true:
		l.add_theme_font_size_override("font_size", fs)
		l.size = Vector2(w, 4.0)
		need = float(l.get_line_count()) * float(l.get_line_height())
		if need <= max_h or fs <= min_fs: break
		fs -= 1
	_put_size(l, Vector2(w, need + 2.0))
	return need + 2.0

var _ch := 0.0           ## the content's top y and height (set by _layout, used by the caption)
var _cy := 0.0
var _cap_x := 0.0
var _cap_w := 0.0

func _layout() -> void:
	if headline == null: return
	var W := size.x
	var H := size.y
	var fits := H >= MIN_H and W >= MIN_W and not weapons.is_empty() and not data.is_empty()
	shown = fits
	mini = not fits and H >= MINI_H and W >= MIN_W and not data.is_empty()
	for c: Control in content: c.visible = fits
	view_clip.visible = fits and has_set()
	if stage != null: stage.active = fits and _vis
	if not fits:
		if mini: _layout_mini(W, H)
		dots.queue_redraw()
		return
	var pad := clampf(H * 0.07, 5.0, 12.0)
	var inner := Rect2(pad + 4.0, pad, W - 2.0 * pad - 8.0, H - 2.0 * pad)
	var ih := minf(inner.size.y, MAX_CONTENT_H)
	var iy := inner.position.y + (inner.size.y - ih) * 0.5
	glass.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)       # a tall band: the glass hugs the content, the scene shows around it
	glass.position = Vector2(0, iy - pad)
	_put_size(glass, Vector2(W, ih + 2.0 * pad))
	_ch = ih
	_cy = iy
	var gap := clampf(ih * 0.12, 8.0, 18.0)
	var x := inner.position.x
	# the lockup: badge, title, tagline
	var lw := clampf(W * 0.25, 190.0, 380.0)
	var bs := clampf(ih * 0.3, 26.0, 80.0)
	badge.custom_minimum_size = Vector2(bs, bs)
	_put_size(badge, Vector2(bs, bs))
	var hl_max := int(clampf(ih * 0.3, 18.0, 64.0))
	var hw := lw - bs - 8.0
	_fit(headline, headline_text(), hl_max, hw, FONT_MIN)
	var hl_h := maxf(bs, float(headline.get_theme_font("font").get_height(headline.get_theme_font_size("font_size"))) + 4.0)
	var tg_h := _fit_wrap(tagline, tr(str(data.get("tagline", ""))), int(clampf(ih * 0.14, 12.0, 26.0)), lw, ih * 0.42, FONT_MIN)
	tagline.visible = hl_h + 4.0 + tg_h <= ih
	if not tagline.visible: tg_h = 0.0
	var total := hl_h + (4.0 + tg_h if tagline.visible else 0.0)
	var y0 := iy + (ih - total) * 0.5
	badge.position = Vector2(x, y0 + (hl_h - bs) * 0.5)
	headline.position = Vector2(x + bs + 8.0, y0)
	_put_size(headline, Vector2(hw, hl_h))
	tagline.position = Vector2(x, y0 + hl_h + 4.0)
	x += lw + gap
	# the stage
	var sw := minf(ih * 1.8, W * 0.26)
	var sh := sw / 1.8
	var srect := Rect2(x, iy + (ih - sh) * 0.5, sw, sh)
	stage_tex.position = srect.position
	_put_size(stage_tex, srect.size)
	if has_set():                                                    # the 3D set fills the glass; its subject shows in the stage slot
		view_clip.position = glass.position
		_put_size(view_clip, Vector2(W, ih + 2.0 * pad))
		stage.frame(Vector2(W, ih + 2.0 * pad), Rect2(srect.position - glass.position, srect.size))
		scrim.queue_redraw()
	var bh := minf(maxf(srect.size.y - 4.0, TOUCH), H - 2.0)
	stage_btn.position = Vector2(srect.position.x + 2.0, srect.get_center().y - bh * 0.5)
	_put_size(stage_btn, Vector2(srect.size.x - 4.0, bh))
	x += sw + gap
	# the weapon caption
	var cw := clampf(W * 0.14, 108.0, 210.0)
	_cap_x = x
	_cap_w = cw
	_layout_caption()
	x += cw + gap
	# the arena, only when it leaves room for the features
	var room := inner.end.x - x
	var asz := clampf(ih * 0.66, 56.0, 230.0)
	var want_arena := H >= 120.0 and room - asz - gap >= 200.0
	arena.visible = want_arena
	arena_name.visible = want_arena and arena_name.text != ""
	if want_arena:
		var nh := 0.0
		if arena_name.visible: nh = _fit_wrap(arena_name, arena_name.text, int(clampf(ih * 0.09, 11.0, 20.0)), asz + 12.0, ih * 0.2, FONT_MIN) + 2.0
		var ay := iy + (ih - asz - nh) * 0.5
		arena.position = Vector2(x, ay)
		_put_size(arena, Vector2(asz, asz))
		arena_name.position = Vector2(x - 6.0, ay + asz + 2.0)
		x += asz + gap
		room = inner.end.x - x
	# the features
	var feat_ok := room >= 150.0
	var ffs := int(clampf(ih * 0.13, 12.0, 26.0))
	var fhs: Array[float] = []
	var total_f := 0.0
	for i in 3:
		var f := feats[i]
		f.visible = feat_ok and f.text != ""
		if not f.visible: continue
		var fh := _fit_wrap(f, f.text, ffs, room - 14.0, ih / 3.0 - 2.0, FONT_MIN)
		fhs.append(fh)
		total_f += fh
	var shown_f := fhs.size()
	while shown_f > 1 and total_f + float(shown_f + 1) * 4.0 > ih:       # too tall at a readable size: the last feature goes
		shown_f -= 1
		total_f -= fhs[shown_f]
	var slot := (ih - total_f) / float(shown_f + 1) if shown_f > 0 else 0.0
	var fy := iy + slot
	var k := 0
	for i in 3:
		var f := feats[i]
		if not f.visible: continue
		if k >= shown_f:
			f.visible = false
			continue
		f.position = Vector2(x + 14.0, fy)
		fy += fhs[k] + slot
		k += 1
	dots.queue_redraw()

## A short band (a phone in landscape with the buy row showing): the lockup in one row, no stage.
func _layout_mini(W: float, H: float) -> void:
	for c: Control in [glass, badge, headline, tagline]: c.visible = true
	glass.position = Vector2.ZERO
	_put_size(glass, Vector2(W, H))
	var pad := 5.0
	var bs := clampf(H - 2.0 * pad, 24.0, 44.0)
	badge.custom_minimum_size = Vector2(bs, bs)
	_put_size(badge, Vector2(bs, bs))
	badge.position = Vector2(pad + 6.0, (H - bs) * 0.5)
	var x := badge.position.x + bs + 10.0
	var hw := clampf(W * 0.3, 150.0, 300.0)
	_fit(headline, headline_text(), int(clampf(H * 0.5, 16.0, 34.0)), hw, FONT_MIN)
	var fh := float(headline.get_theme_font("font").get_height(headline.get_theme_font_size("font_size"))) + 4.0
	headline.position = Vector2(x, (H - fh) * 0.5)
	_put_size(headline, Vector2(hw, fh))
	x += hw + 12.0
	var tw := W - x - pad - 8.0
	_fit(tagline, tr(str(data.get("tagline", ""))), int(clampf(H * 0.36, 14.0, 20.0)), tw, FONT_MIN)
	var tf := tagline.get_theme_font("font")
	tagline.visible = tf.get_string_size(tagline.text, HORIZONTAL_ALIGNMENT_LEFT, -1, tagline.get_theme_font_size("font_size")).x <= tw
	var th := float(tagline.get_theme_font("font").get_height(tagline.get_theme_font_size("font_size"))) + 4.0
	tagline.position = Vector2(x, (H - th) * 0.5)
	_put_size(tagline, Vector2(tw, th))

func _layout_caption() -> void:
	if w_name == null or not shown: return
	var ih := _ch
	var nh := _fit_wrap(w_name, w_name.text, int(clampf(ih * 0.17, 13.0, 30.0)), _cap_w, ih * 0.34, FONT_MIN)
	var rh := _fit_wrap(w_role, w_role.text, int(clampf(ih * 0.125, 11.0, 22.0)), _cap_w, ih * 0.36, FONT_MIN)
	w_role.visible = shown and w_role.text != "" and nh + 3.0 + rh <= ih
	if not w_role.visible: rh = -3.0
	var total := nh + 3.0 + rh
	var y := _cy + (ih - total) * 0.5
	w_name.position = Vector2(_cap_x, y)
	w_role.position = Vector2(_cap_x, y + nh + 3.0)

# ---------------- running ----------------

func _process(dt: float) -> void:
	var covered := _cover != null and is_instance_valid(_cover) and _cover.visible
	var vis := is_visible_in_tree() and not covered
	var hub_vis := scene != null and scene.get_parent() != null and (scene.get_parent() as Control).is_visible_in_tree() and not covered
	if scene != null and scene.active != hub_vis: scene.active = hub_vis
	var on := vis and shown
	if on != _vis:
		_vis = on
		if stage != null: stage.active = on
	if not on: return
	if _arena_due and arena.visible:
		_arena_due = false
		_build_arena()
	if stage != null and stage.spin:
		_auto += dt
		if _auto >= CYCLE_S: cycle(1)

## The arena thumbnail, drawn once (the pack's generator is cached per seed).
func _build_arena() -> void:
	var st: Resource = PackRegistry.style(pack_id)
	if st == null: return
	var aid := str(st.get("arena_id"))
	if _arena_for == aid: return
	_arena_for = aid
	arena.pack_id = pack_id
	arena.set_map(PackLandingArena.map_for(aid, int(data.get("arena_seed", 7))))
