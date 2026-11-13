class_name BuildHud
extends Control
## Sandbox build mode (the web game's Wobble Workshop: B places a 2 m block where you aim, N removes the one you aim at;
## public/index.html ~8442-8460), touch first. World adds it under $UI (last, so its _input sees touches before the
## touch layer) when `world.build_mode` is on, on the 'custom' arena with no bots, crates or moving floor.
## You walk around as usual (stick, look, jump); a see-through brush shows where Place puts blocks and a red box which
## block Remove takes. The palette has four tools, each at least MIN_TAP (44 pt) square:
##   Place   puts the brush (size x size cells, `height` blocks tall) in front of the crosshair hit
##   Remove  takes the aimed block (and the brush around it) away
##   Style   opens the colour / size / height panel (and Clear all)
##   Play    saves and starts a match with bots on the arena (ModeRules sandbox: first to SANDBOX_LIMIT)
## Keys: B place, N remove, C style, P play. The palette sits at the bottom between the move stick side and the touch
## buttons (the HUD's hotbar slot, which build mode hides with the score, radar and health), the status line above it,
## the style panel above that; nothing overlaps the touch buttons, pause or emote button (tests/hud_test.gd).
## Every change goes to the Save profile (Save.set_sandbox: cfg.custom / cfg.blocks / cfg.blockCols, the web shape)
## a moment later, and at once on Play.

signal play_requested

const MIN_TAP := 60.0              ## 44 pt in canvas units (540 canvas units ~ 393 pt on a landscape phone)
const TOOL := Vector2(100, 64)
const GAP := 8.0
const SWATCH := 60.0
const SAVE_DELAY := 0.8
const TOOLS := [["place", "Place", "B"], ["remove", "Remove", "N"], ["style", "Style", "C"], ["play", "Play", "P"]]

var world: Node                    ## world/world.gd
var layout: SandboxLayout
var bar: HBoxContainer
var status: Label
var panel: PanelContainer          ## the Style panel
var tool_bs := {}                  ## tool id -> Button
var color_bs := {}                 ## colour -> Button
var size_bs := {}
var height_bs := {}
var blocks_root: Node3D            ## block meshes (world space)
var ghost_root: Node3D             ## the brush preview + the remove marker
var _ghosts: Array = []            ## pooled MeshInstance3D
var _rm_ghost: MeshInstance3D
var _solids: Array = []            ## the block solids added to world.sim.solids
var _save_t := -1.0
var _touches := {}                 ## touch index -> true (touches this HUD took)
var _target := []                  ## [anchor Vector2, yb] of Place
var _rm_i := -1                    ## block Remove would take

func _init() -> void:
	name = "BuildHud"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

## Takes over the world's custom arena: the saved layout, its blocks as meshes + solids, the HUD panels it does not need.
func bind(w: Node) -> void:
	world = w
	if layout == null: layout = SandboxLayout.new(_save().sandbox_cfg())
	if bar == null: _build_ui()
	if blocks_root == null or not is_instance_valid(blocks_root):
		blocks_root = Node3D.new(); blocks_root.name = "BuildBlocks"
		ghost_root = Node3D.new(); ghost_root.name = "BuildGhost"
		_rm_ghost = null; _ghosts = []
	if blocks_root.get_parent(): blocks_root.get_parent().remove_child(blocks_root)
	if ghost_root.get_parent(): ghost_root.get_parent().remove_child(ghost_root)
	world.map_node.add_child(blocks_root)
	world.map_node.add_child(ghost_root)
	_solids = []
	_rebuild()
	for n: String in ["Score", "Radar", "Health", "Hotbar", "Feed"]:
		var c: Node = world.hud.get_node_or_null(n)
		if c: c.visible = false
	_refresh()

## The block meshes and solids from `layout` (after every change).
func _rebuild() -> void:
	for c in blocks_root.get_children():
		blocks_root.remove_child(c); c.queue_free()
	var boxes: Array = []
	for i in layout.blocks.size(): boxes.append(SandboxLayout.box_of(layout.blocks[i], layout.color_of(i)))
	MapBuilder._add_boxes(blocks_root, boxes)
	var live: Array = world.sim.solids
	for s: Dictionary in _solids:
		var k := live.find(s)
		if k >= 0: live.remove_at(k)
	_solids = []
	for b: Array in layout.blocks:
		var s := SandboxLayout.solid_of(b)
		live.append(s); _solids.append(s)

# ============================== actions ==============================

func _bodies() -> Array:
	var out: Array = []
	for f: FighterState in world.sim.fighters:
		if not f.dead: out.append(Vector3(f.phys.px, f.phys.py, f.phys.pz))
	return out

func _aim() -> Array:
	var cam: Camera3D = world.cam
	var p: FighterState = world.sim.player
	return [world.cam.aim_point, -cam.global_transform.basis.z, Vector3(p.phys.px, p.phys.py, p.phys.pz), p.yaw]

func place_now() -> int:
	var a := _aim()
	var t: Array = layout.place_target(a[0], a[1], a[2], a[3])
	var r := layout.place(t[0], t[1], _bodies())
	var n: int = (r["added"] as Array).size()
	if r["why"] == "full": world._toast(tr("Easy there! That's a lot of blocks (%d max)") % SandboxLayout.MAX_BLOCKS)
	elif n == 0 and r["why"] == "blocked": world._toast("Someone is in the way. Rude")
	elif n == 0: world._toast("No room there. Too snug")
	if n > 0: _changed("clink")
	return n

func remove_now() -> int:
	var a := _aim()
	var i := layout.remove_target(a[0], a[1], a[2], a[3])
	var n := layout.remove(i).size()
	if n == 0: world._toast("Aim at a block to remove it. Then poof!")
	else: _changed("clink")
	return n

func clear_all() -> void:
	if layout.count() == 0: return
	layout.clear()
	world._toast("Blocks cleared. Fresh start")
	_changed("")

func set_color(c: int) -> void:
	layout.color = c; _refresh()

func set_brush(s: int) -> void:
	layout.size = clampi(s, 1, 3); _refresh()

func set_height(h: int) -> void:
	layout.height = clampi(h, 1, 4); _refresh()

func toggle_style(on: Variant = null) -> void:
	panel.visible = (not panel.visible) if on == null else bool(on)
	_refresh()

## Saves now and asks the world for a match on this arena.
func play() -> void:
	save_now()
	play_requested.emit()

## The Save autoload (looked up: class_name scripts compile before the autoloads exist in --script runs).
func _save() -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node("Save")

func _exit_tree() -> void:
	if _save_t > 0.0: save_now()       # leaving (title, Play) with a change not written yet

func save_now() -> void:
	_save_t = -1.0
	_save().set_sandbox(layout.to_cfg())

func _changed(sfx: String) -> void:
	_rebuild()
	_save_t = SAVE_DELAY
	if sfx != "" and get_tree().root.has_node("Sfx"): get_tree().root.get_node("Sfx").play(sfx)    # the web sfx('clink')
	_refresh()

func _tool(id: String) -> void:
	match id:
		"place": place_now()
		"remove": remove_now()
		"style": toggle_style()
		"play": play()

# ============================== UI ==============================

func _button(text: String, sz: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = sz
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 22)
	return b

func _build_ui() -> void:
	bar = HBoxContainer.new()
	bar.name = "Palette"
	bar.add_theme_constant_override("separation", int(GAP))
	add_child(bar)
	for t: Array in TOOLS:
		var b := _button(t[1], TOOL)
		b.name = t[0]
		b.tooltip_text = tr("%s (%s)") % [tr(t[1]), t[2]]
		b.pressed.connect(_tool.bind(t[0]))
		bar.add_child(b)
		tool_bs[t[0]] = b
		JuicyButton.attach(b)
	(tool_bs["play"] as Button).theme_type_variation = &"PrimaryButton"
	status = Label.new()
	status.name = "Status"
	status.theme_type_variation = &"HudLabel"
	status.add_theme_font_size_override("font_size", 18)
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(status)
	panel = PanelContainer.new()
	panel.name = "Style"
	panel.theme_type_variation = &"HudPanel"
	panel.visible = false
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", int(GAP))
	panel.add_child(v)
	var cr := HBoxContainer.new(); cr.name = "Colours"; cr.add_theme_constant_override("separation", int(GAP)); v.add_child(cr)
	for i in SandboxLayout.COLORS.size():
		var c: int = SandboxLayout.COLORS[i]
		var b := _button("", Vector2(SWATCH, SWATCH))
		b.name = SandboxLayout.COLOR_NAMES[i]
		b.tooltip_text = SandboxLayout.COLOR_NAMES[i]
		b.toggle_mode = true
		b.icon = _swatch(c, 30)
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.pressed.connect(set_color.bind(c))
		cr.add_child(b); color_bs[c] = b
	_pill_row(v, "Size", "Size", SandboxLayout.SIZES, ["1×1", "2×2", "3×3"], size_bs, set_brush)
	_pill_row(v, "Height", "Height", SandboxLayout.HEIGHTS, ["1", "2", "3", "4"], height_bs, set_height)
	var br := HBoxContainer.new(); br.name = "Actions"; br.add_theme_constant_override("separation", int(GAP)); v.add_child(br)
	var clr := _button("Clear all", Vector2(150, MIN_TAP)); clr.name = "Clear"
	clr.pressed.connect(clear_all); br.add_child(clr)
	var sp := Control.new(); sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL; br.add_child(sp)
	var done := _button("Done", Vector2(120, MIN_TAP)); done.name = "Done"
	done.theme_type_variation = &"PrimaryButton"
	done.pressed.connect(toggle_style.bind(false)); br.add_child(done)

func _pill_row(parent: Control, row_name: String, label: String, keys: Array, names: Array, store: Dictionary, on_pick: Callable) -> void:
	var h := HBoxContainer.new(); h.name = row_name; h.add_theme_constant_override("separation", int(GAP)); parent.add_child(h)
	var l := Label.new(); l.text = label; l.custom_minimum_size = Vector2(80, 0); l.theme_type_variation = &"HudLabel"
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	for i in keys.size():
		var b := _button(names[i], Vector2(MIN_TAP + 6.0, MIN_TAP))
		b.name = str(keys[i])
		b.toggle_mode = true
		b.pressed.connect(on_pick.bind(keys[i]))
		h.add_child(b); store[keys[i]] = b

static func _swatch(c: int, s: int) -> ImageTexture:
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(MapBuilder.hex(c))
	for i in s:                                   # a thin dark edge so white and yellow read on light buttons
		for e: Vector2i in [Vector2i(i, 0), Vector2i(i, s - 1), Vector2i(0, i), Vector2i(s - 1, i)]: img.set_pixelv(e, Color(0, 0, 0, 0.5))
	return ImageTexture.create_from_image(img)

func _refresh() -> void:
	if layout == null or bar == null: return
	for c: int in color_bs: (color_bs[c] as Button).set_pressed_no_signal(c == layout.color)
	for k: int in size_bs: (size_bs[k] as Button).set_pressed_no_signal(k == layout.size)
	for k: int in height_bs: (height_bs[k] as Button).set_pressed_no_signal(k == layout.height)
	var st: Button = tool_bs["style"]
	st.icon = _swatch(layout.color, 18)
	st.set_pressed_no_signal(panel.visible)
	status.text = tr("Blocks %d / %d · %d×%d, %d high") % [layout.count(), SandboxLayout.MAX_BLOCKS, layout.size, layout.size, layout.height]

## Palette, status and panel rects (tests): bottom of the safe area, between the stick side and the touch buttons.
func layout_ui() -> void:
	var vs := get_viewport_rect().size
	var touch: Control = world.touch if world else null
	var ins: Array = touch.safe_insets() if touch and touch.has_method("safe_insets") else [0.0, 0.0, 0.0, 0.0]
	var safe := Rect2(Vector2(ins[0], ins[1]), vs - Vector2(ins[0] + ins[2], ins[1] + ins[3])).grow(-8.0)
	bar.reset_size()
	var w := bar.size.x
	var x := vs.x / 2.0 - w / 2.0
	if touch and touch.visible:
		var lefty := bool(touch.get("lefty"))
		var edge := INF if not lefty else -INF
		for b: Array in touch.BUTTONS:
			var r: Array = touch.button_rect(b)
			edge = maxf(edge, r[0].x + r[1]) if lefty else minf(edge, r[0].x - r[1])
		x = (edge + 12.0) if lefty else (edge - 12.0 - w)
		x = clampf(x, safe.position.x, safe.end.x - w)
	bar.position = Vector2(x, safe.end.y - bar.size.y)
	status.reset_size()
	status.position = Vector2(bar.position.x + w / 2.0 - status.size.x / 2.0, bar.position.y - status.size.y - 6.0)
	if panel.visible:
		panel.reset_size()
		var px := clampf(bar.position.x + w / 2.0 - panel.size.x / 2.0, safe.position.x, safe.end.x - panel.size.x)
		panel.position = Vector2(px, status.position.y - panel.size.y - 8.0)

## Rects that take taps (canvas units): the tool buttons and, while open, the panel.
func tap_rects() -> Array:
	var out: Array = []
	for b: Button in tool_bs.values(): out.append(b.get_global_rect())
	if panel.visible: out.append(panel.get_global_rect())
	return out

# ============================== input ==============================

## Touches on the palette / panel press its buttons here, before the touch layer turns them into look or move.
func _input(e: InputEvent) -> void:
	if world == null or not visible or world.paused: return
	if e is InputEventScreenTouch:
		var st := e as InputEventScreenTouch
		var p := (make_input_local(st) as InputEventScreenTouch).position
		if st.pressed:
			var b := _button_at(p)
			var on_panel := panel.visible and panel.get_global_rect().has_point(p)
			if b != null or on_panel:
				_touches[st.index] = true
				if b != null: b.pressed.emit()
				get_viewport().set_input_as_handled()
		elif _touches.has(st.index):
			_touches.erase(st.index)
			get_viewport().set_input_as_handled()
	elif e is InputEventScreenDrag and _touches.has((e as InputEventScreenDrag).index):
		get_viewport().set_input_as_handled()

func _button_at(p: Vector2) -> Button:
	var all: Array = tool_bs.values()
	if panel.visible:
		all += color_bs.values() + size_bs.values() + height_bs.values()
		for n: String in ["Actions/Clear", "Actions/Done"]:
			var c: Node = panel.get_child(0).get_node_or_null(n)
			if c: all.append(c)
	for b: Button in all:
		if b.is_visible_in_tree() and b.get_global_rect().grow(2.0).has_point(p): return b
	return null

func _unhandled_key_input(e: InputEvent) -> void:
	if world == null or not visible or world.paused or not (e is InputEventKey) or not e.pressed or e.echo: return
	var k := (e as InputEventKey).physical_keycode
	var id: String = {KEY_B: "place", KEY_N: "remove", KEY_C: "style", KEY_P: "play"}.get(k, "")
	if id != "":
		_tool(id)
		get_viewport().set_input_as_handled()

# ============================== per frame ==============================

func _process(dt: float) -> void:
	if world == null or world.sim == null or not is_instance_valid(blocks_root): return
	if _save_t > 0.0:
		_save_t -= dt
		if _save_t <= 0.0: save_now()
	layout_ui()
	_update_ghost()

var _mats := {}

func _ghost_mat(c: Color) -> StandardMaterial3D:
	if _mats.has(c): return _mats[c]
	var m := StandardMaterial3D.new()
	_mats[c] = m
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = c
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	return m

## The brush preview (see-through, the brush colour) and the red marker on the block Remove would take.
func _update_ghost() -> void:
	var a := _aim()
	_target = layout.place_target(a[0], a[1], a[2], a[3])
	_rm_i = layout.remove_target(a[0], a[1], a[2], a[3])
	var cells: Array = []
	for c: Vector2 in layout.brush_cells(_target[0]):
		if not layout.in_bounds(c.x, c.y): continue
		for h in layout.height:
			var y: float = float(_target[1]) + h * SandboxLayout.CELL
			if y <= SandboxLayout.MAX_YB and layout.index_of(c.x, y, c.y) < 0: cells.append(Vector3(c.x, y, c.y))
	while _ghosts.size() < cells.size():
		var g := MeshInstance3D.new()
		var bm := BoxMesh.new(); bm.size = Vector3.ONE * 1.96
		g.mesh = bm
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ghost_root.add_child(g)
		_ghosts.append(g)
	var col := MapBuilder.hex(layout.color)
	col.a = 0.42 if not layout.full() else 0.15
	var mat := _ghost_mat(col)
	for i in _ghosts.size():
		var g: MeshInstance3D = _ghosts[i]
		g.visible = i < cells.size()
		if g.visible:
			g.position = cells[i] + Vector3(0, SandboxLayout.CELL / 2.0, 0)
			g.material_override = mat
	if _rm_ghost == null:
		_rm_ghost = MeshInstance3D.new()
		var bm2 := BoxMesh.new(); bm2.size = Vector3.ONE * 2.08
		_rm_ghost.mesh = bm2
		_rm_ghost.material_override = _ghost_mat(Color(0.94, 0.33, 0.31, 0.38))
		_rm_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ghost_root.add_child(_rm_ghost)
	_rm_ghost.visible = _rm_i >= 0
	if _rm_i >= 0:
		var b: Array = layout.blocks[_rm_i]
		_rm_ghost.position = Vector3(float(b[0]), float(b[1]) + SandboxLayout.CELL / 2.0, float(b[2]))

## Where Place would go right now (tests): [anchor, yb].
func place_target() -> Array:
	return _target
