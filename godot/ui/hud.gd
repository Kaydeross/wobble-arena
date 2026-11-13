class_name MatchHud
extends Control
## In-match HUD (ui/hud.tscn). Reads the match through World (sim, camera, touch layer) and never changes it.
## Top left: K.O. count + clock + leader. Top right: radar, kill feed below it. Bottom left: health bar.
## Bottom centre: hotbar (fits between the health bar and the touch buttons when those show). Floating nameplates
## over the 3 nearest fighters, a crosshair, toasts. Everything stays inside the safe area and clear of the touch
## layer's pause button. World calls bind() once and update(delta) every rendered frame.

const PAD := 14.0
const FEED_TIME := 5.0
const FEED_MAX := 4
const TOAST_TIME := 2.2
const TOP_STACK := 70.0           ## what hangs under the toast (team board, mode line, spectator line) starts this far below the top inset

var world: Node
var sim: MatchSim
var last_touch := false          ## the last input was a touch (hides the keybind badges)

var _ins := [0.0, 0.0, 0.0, 0.0]
var _ko_panel: PanelContainer
var _ko_n: Label
var _clock: Label
var _leader: Label
var _crown: Control
var _radar: Control
var _feed: VBoxContainer
var _feed_items: Array = []      ## [node, time left]
var _toast: PanelContainer
var _toast_l: Label
var _toast_t := 0.0
var _health: Control
var _hotbar: Control
var _plates: Control
var _cross: Control
var _hint: Label
var _center: Label
var _last_ko := -1

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plates = preload("res://ui/hud_nameplates.gd").new()
	_plates.name = "Nameplates"
	add_child(_plates)
	_cross = Control.new()
	_cross.name = "Crosshair"
	_cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cross.draw.connect(_draw_cross)
	add_child(_cross)
	_build_ko()
	_radar = preload("res://ui/hud_radar.gd").new()
	_radar.name = "Radar"
	add_child(_radar)
	_feed = VBoxContainer.new()
	_feed.name = "Feed"
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_feed.add_theme_constant_override("separation", 5)
	add_child(_feed)
	_health = preload("res://ui/hud_health.gd").new()
	_health.name = "Health"
	add_child(_health)
	_hotbar = preload("res://ui/hud_hotbar.gd").new()
	_hotbar.name = "Hotbar"
	add_child(_hotbar)
	_hint = Label.new()
	_hint.name = "Hint"
	_hint.theme_type_variation = &"HudLabel"
	_hint.add_theme_font_size_override("font_size", 16)
	_hint.add_theme_constant_override("outline_size", 4)
	_hint.add_theme_color_override("font_outline_color", UiTheme.INK)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hint)
	_center = Label.new()
	_center.name = "Center"
	_center.theme_type_variation = &"HudLabel"
	_center.add_theme_font_size_override("font_size", 34)
	_center.add_theme_color_override("font_color", UiTheme.ACCENT)
	_center.add_theme_constant_override("outline_size", 6)
	_center.add_theme_color_override("font_outline_color", UiTheme.INK)
	_center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_center)
	_build_toast()
	get_viewport().size_changed.connect(_update_insets)
	get_tree().root.window_input.connect(_on_window_input)
	_update_insets()

func bind(w: Node) -> void:
	world = w
	sim = w.sim
	_plates.sim = sim
	_plates.cam = w.cam
	_radar.sim = sim
	last_touch = w.touch.visible
	if w.touch.has_method("attach"):
		w.touch.attach(sim, _hotbar)      # context button + tappable hotbar slots
	for it: Array in _feed_items: it[0].queue_free()
	_feed_items.clear()
	_last_ko = -1

func _update_insets() -> void:
	_ins = SafeArea.insets(get_viewport())

func _on_window_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch or e is InputEventScreenDrag:
		last_touch = true
	elif e is InputEventKey or e is InputEventJoypadButton or (e is InputEventMouseButton and not e.is_echo()):
		if e is InputEventMouseButton and (e as InputEventMouseButton).device == InputEvent.DEVICE_ID_EMULATION: return
		last_touch = false

# ---------------- building ----------------

func _build_ko() -> void:
	_ko_panel = PanelContainer.new()
	_ko_panel.name = "Score"
	_ko_panel.theme_type_variation = &"HudPanel"
	_ko_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ko_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", -2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ko_panel.add_child(col)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(row)
	var tag := _lbl(row, 16, UiTheme.ACCENT)
	tag.text = "K.O."
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_ko_n = _lbl(row, 30, Color.WHITE)
	_ko_n.text = "0"
	_ko_n.pivot_offset = Vector2(9, 18)
	var sep := ColorRect.new()
	sep.color = Color(1, 1, 1, 0.2)
	sep.custom_minimum_size = Vector2(2, 24)
	sep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(sep)
	_clock = _lbl(row, 24, Color.WHITE)
	_clock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var lrow := HBoxContainer.new()
	lrow.add_theme_constant_override("separation", 6)
	lrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(lrow)
	_crown = Control.new()
	_crown.custom_minimum_size = Vector2(18, 14)
	_crown.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_crown.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crown.draw.connect(func():
		var c := UiTheme.ACCENT
		_crown.draw_colored_polygon(PackedVector2Array([Vector2(1, 13), Vector2(1, 3), Vector2(5.5, 7), Vector2(9, 1), Vector2(12.5, 7), Vector2(17, 3), Vector2(17, 13)]), c)
		_crown.draw_rect(Rect2(1, 11, 16, 2.5), c.darkened(0.25)))
	lrow.add_child(_crown)
	_leader = _lbl(lrow, 15, UiTheme.MUTED)
	_leader.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_leader.custom_minimum_size.x = 120

func _build_toast() -> void:
	_toast = PanelContainer.new()
	_toast.name = "Toast"
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := UiTheme.box(Color(UiTheme.PANEL.r, UiTheme.PANEL.g, UiTheme.PANEL.b, 0.88), 99, UiTheme.ACCENT, 2, 8)
	sb.content_margin_left = 18; sb.content_margin_right = 18; sb.content_margin_top = 3; sb.content_margin_bottom = 5
	_toast.add_theme_stylebox_override("panel", sb)
	_toast_l = _lbl(_toast, 21, UiTheme.ACCENT)
	_toast_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.visible = false
	add_child(_toast)

func _lbl(parent: Node, fs: int, c: Color) -> Label:
	var l := Label.new()
	l.theme_type_variation = &"HudLabel"
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", c)
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", UiTheme.INK)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l

# ---------------- events from World ----------------

func clear_toast() -> void:
	_toast_t = 0.0
	_toast.visible = false

func toast(t: String) -> void:
	if world != null and world.has_method("results_open") and world.results_open(): return   # the results panel has the stage
	_toast_l.text = t
	_toast_t = TOAST_TIME
	_toast.visible = true
	_toast.reset_size()
	_toast.pivot_offset = _toast.size / 2.0
	_toast.scale = Vector2(0.6, 0.6)
	_toast.modulate.a = 0.0
	var tw := _toast.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_toast, "scale", Vector2.ONE, 0.28)
	tw.parallel().tween_property(_toast, "modulate:a", 1.0, 0.12)

## One kill-feed line: killer [weapon] victim, or "victim fell off".
func add_feed(killer: FighterState, victim: FighterState, weapon: String, fell: bool) -> void:
	var item := PanelContainer.new()
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := UiTheme.box(Color(UiTheme.PANEL.r, UiTheme.PANEL.g, UiTheme.PANEL.b, 0.78), 12, Color(1, 1, 1, 0.12), 2, 3)
	sb.content_margin_left = 10; sb.content_margin_right = 10; sb.content_margin_top = 2; sb.content_margin_bottom = 3
	var mine := killer != null and killer == sim.player
	if mine: sb.border_color = Color(UiTheme.ACCENT.r, UiTheme.ACCENT.g, UiTheme.ACCENT.b, 0.8)
	item.add_theme_stylebox_override("panel", sb)
	item.size_flags_horizontal = Control.SIZE_SHRINK_END
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item.add_child(row)
	if killer != null:
		_lbl(row, 15, _who_color(killer)).text = _who(killer)
		var wl := _lbl(row, UiTheme.MIN_FONT, UiTheme.INK)
		wl.text = tr(weapon) if weapon != "" else "K.O."
		var ws := UiTheme.box(Color(1, 1, 1, 0.8), 6, Color(0, 0, 0, 0), 0, 0)
		ws.content_margin_left = 5; ws.content_margin_right = 5; ws.content_margin_top = 0; ws.content_margin_bottom = 0
		wl.add_theme_stylebox_override("normal", ws)
		wl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_lbl(row, 15, _who_color(victim)).text = _who(victim)
	else:
		_lbl(row, 15, _who_color(victim)).text = _who(victim)
		_lbl(row, 15, UiTheme.MUTED).text = "fell off" if fell else "was K.O.'d"
	_feed.add_child(item)
	_feed.move_child(item, 0)
	_feed_items.push_front([item, FEED_TIME])
	while _feed_items.size() > FEED_MAX:
		var old: Array = _feed_items.pop_back()
		old[0].queue_free()
	item.modulate.a = 0.0
	var tw := item.create_tween()
	tw.tween_property(item, "modulate:a", 1.0, 0.18)

func _who(f: FighterState) -> String:
	return "You" if f == sim.player else f.name

func _who_color(f: FighterState) -> Color:
	return UiTheme.ACCENT if f == sim.player else Color.WHITE

# ---------------- per frame ----------------

func update(delta: float) -> void:
	if sim == null or world == null: return
	var vs := get_viewport_rect().size
	var safe := Rect2(Vector2(_ins[0], _ins[1]), vs - Vector2(_ins[0] + _ins[2], _ins[1] + _ins[3])).grow(-PAD)
	var touch: Control = world.touch
	var touch_on: bool = touch.visible
	var p := sim.player
	# --- score pill + leader
	if p.ko != _last_ko:
		if _last_ko >= 0 and p.ko > _last_ko:
			var tw := _ko_n.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			_ko_n.scale = Vector2(1.5, 1.5)
			tw.tween_property(_ko_n, "scale", Vector2.ONE, 0.35)
		_last_ko = p.ko
		_ko_n.text = str(p.ko)
	var t := int(sim.elapsed())
	_clock.text = "%d:%02d" % [t / 60, t % 60]
	var lead: FighterState = null
	for f: FighterState in sim.fighters:
		if f.ko > 0 and (lead == null or f.ko > lead.ko): lead = f
	_crown.visible = lead != null
	_leader.text = (tr("You lead with %d") % lead.ko if lead == p else "%s  %d" % [lead.name, lead.ko]) if lead else "No leader yet. Be first!"
	_leader.add_theme_color_override("font_color", UiTheme.ACCENT if lead == p else UiTheme.MUTED)
	# keep clear of the touch layer's pause button
	var pause_r := Rect2()
	if touch_on and touch.has_method("pause_rect"):
		pause_r = touch.pause_rect()
	_ko_panel.reset_size()
	var ko_x := safe.position.x
	if pause_r.size.x > 0.0 and pause_r.get_center().x < vs.x * 0.5:
		ko_x = maxf(ko_x, pause_r.end.x + 10.0)
	_ko_panel.position = Vector2(ko_x, safe.position.y)
	# --- radar + feed (top right)
	var rx := safe.end.x - _radar.size.x
	if pause_r.size.x > 0.0 and pause_r.get_center().x > vs.x * 0.5:
		rx = minf(rx, pause_r.position.x - 10.0 - _radar.size.x)
	_radar.position = Vector2(rx, safe.position.y)
	_radar.yaw = world.cam.yaw
	_radar.tick(delta)
	for i in range(_feed_items.size() - 1, -1, -1):
		var it: Array = _feed_items[i]
		it[1] -= delta
		if it[1] <= 0.0:
			it[0].queue_free(); _feed_items.remove_at(i)
		elif it[1] < 0.5:
			it[0].modulate.a = it[1] / 0.5
	_feed.reset_size()
	_feed.position = Vector2(rx + _radar.size.x - _feed.size.x, safe.position.y + _radar.size.y + 10.0)
	# --- health (bottom left; bottom right when the touch buttons sit on the left)
	var lefty: bool = touch_on and bool(touch.get("lefty"))
	var mx := sim.combat.max_hp(p)
	var k := clampf(p.hp / mx, 0.0, 1.0) if not p.dead else 0.0
	_health.set_value(k, "%d / %d" % [ceili(maxf(p.hp, 0.0)) if not p.dead else 0, roundi(mx)],
		tr(str(sim.combat.classes.get(p.class_id, {}).get("name", p.class_id))))
	_health.tick(delta)
	var hy := safe.end.y - _health.size.y
	_health.position = Vector2(safe.end.x - _health.size.x if lefty else safe.position.x, hy)
	# --- hotbar: centred, or fitted between the health bar and the touch buttons
	_fill_hotbar(p)
	_hotbar.show_keys = not last_touch
	_hotbar.tick(delta)
	var lo := 0.0
	var hi := vs.x
	if touch_on and touch.has_method("button_rect"):
		var bx := _touch_buttons_x(touch, lefty)
		if lefty:
			lo = bx + 10.0; hi = _health.position.x - 10.0
		else:
			lo = _health.position.x + _health.size.x + 10.0; hi = bx - 10.0
	# touch: narrower slots first, so the slots stay finger-sized (44 pt at the UI scale) before the bar scales down
	_hotbar.set_slot_w((hi - lo - _hotbar.GAP * 3.0) / 4.0 if touch_on else 104.0)
	var hw: float = _hotbar.custom_minimum_size.x
	var sc := clampf((hi - lo) / hw, 0.55, 1.0) if touch_on else 1.0
	_hotbar.scale = Vector2(sc, sc)
	var hx := (lo + hi) / 2.0 - hw * sc / 2.0 if touch_on else vs.x / 2.0 - hw / 2.0
	_hotbar.position = Vector2(hx, safe.end.y - _hotbar.custom_minimum_size.y * sc + 4.0)
	# --- hint, centre message, crosshair, nameplates, toast
	var hint := ""
	if Tier.is_pc() and not touch_on and not world.input.mouse_captured() and not world.paused:
		hint = "Click to look around · Esc: menu"
	_hint.text = hint
	_hint.visible = hint != ""
	_hint.reset_size()
	_hint.position = Vector2(vs.x / 2.0 - _hint.size.x / 2.0, _hotbar.position.y - _hint.size.y - 6.0)
	_center.text = "Respawning… shake it off" if p.dead and not p.elim else ""     # out for good (Sudden Death): the spectator line says it
	_center.visible = p.dead and not p.elim
	_center.reset_size()
	_center.position = Vector2(vs.x / 2.0 - _center.size.x / 2.0, vs.y * 0.38)
	_cross.position = vs / 2.0
	_cross.queue_redraw()
	_plates.size = vs
	_plates.tick(delta)
	if _toast.visible:
		_toast_t -= delta
		_toast.position = Vector2(vs.x / 2.0 - _toast.size.x / 2.0, safe.position.y + 6.0)      # top edge: never over the action
		if _toast_t < 0.3: _toast.modulate.a = maxf(_toast_t / 0.3, 0.0)
		if _toast_t <= 0.0: _toast.visible = false

## Leftmost (or, left-handed, rightmost) edge of the touch buttons.
func _touch_buttons_x(touch: Control, lefty: bool) -> float:
	var x := INF if not lefty else -INF
	for b: Array in touch.BUTTONS:
		var r: Array = touch.button_rect(b)
		var c: Vector2 = r[0]
		var rad: float = r[1]
		x = maxf(x, c.x + rad) if lefty else minf(x, c.x - rad)
	return x

func _fill_hotbar(p: FighterState) -> void:
	var out: Array = []
	for i in 3:
		var s: Variant = p.slots[i] if i < p.slots.size() else null
		if s == null:
			out.append({"name": tr("empty"), "ammo": "", "sub": "", "low": false, "empty": true, "active": false, "reload": -1.0})
			continue
		var w := sim.combat.wdata(str(s["key"]))
		var ammo := ""        # the big number: bullets in the magazine (or uses left)
		var sub := ""         # the small number after it: spare ammo
		var low := false
		if str(s["key"]) == "blower":
			ammo = "%d%%" % maxi(0, ceili(float(s["ammo"])))      # the web hotbar shows the blower in %
			low = float(s["ammo"]) <= 20.0
		elif int(s["mag"]) >= 0:
			ammo = str(int(s["mag"]))
			sub = "/" + str(int(s["ammo"]))
			low = int(s["mag"]) <= maxi(1, int(ceil(float(w.get("mag", 0)) * 0.25)))
		elif int(s["ammo"]) > 1:
			ammo = "x%d" % int(s["ammo"])
			low = int(s["ammo"]) <= 2
		var active := p.slot == i and not p.dead
		var rl := -1.0
		if active and p.reloading and p.rl_dur > 0.0: rl = p.rl_t / p.rl_dur
		out.append({"name": tr(str(w.get("name", s["key"]))), "ammo": ammo, "sub": sub, "low": low, "empty": false, "active": active, "reload": rl})
	var sp := sim.combat.wdata("spatula")
	out.append({"name": tr(str(sp.get("name", "Spatula"))), "ammo": "", "sub": "", "low": false, "empty": false, "active": p.slot < 0 and not p.dead, "reload": -1.0})
	_hotbar.slots = out

func _draw_cross() -> void:
	var ink := Color(UiTheme.INK.r, UiTheme.INK.g, UiTheme.INK.b, 0.7)
	for d: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		_cross.draw_line(d * 5.0, d * 12.0, ink, 4.0, true)
		_cross.draw_line(d * 5.5, d * 11.5, Color(1, 1, 1, 0.95), 2.0, true)
	_cross.draw_circle(Vector2.ZERO, 2.4, ink)
	_cross.draw_circle(Vector2.ZERO, 1.4, Color.WHITE)
