class_name EmoteWheel
extends Control
## In-match emotes. One small round button (a smiley) just under the touch layer's pause button, on the same side, so
## the four main action buttons stay four. Tap it: a wheel of your emotes opens around the middle of the screen (the
## Save's wheel_emotes(): the three slots first, then the rest you own, 8 at most); tap one to dance, tap anywhere
## else to close. The dance is the Wobbler's (actors/emote_poses.gd), so the bots and everyone on screen see it.
## Keyboard (web keys): T, G, H play emote slot 1, 2, 3. Hidden while paused, spectating, dead, or on the results.
## Input: this node sits after TouchControls in World's UI layer, so its _input runs first; it only takes the touches
## that start on the button or while the wheel is open, and lets every other touch through to the touch layer.
## World sets `world` (needs touch, player_view, paused, spectating, _results).

signal played(id: String)

const BTN := 62.0              ## button size, canvas units (45 pt at the UI scale, ui/ui_scale.gd)
const GAP := 12.0              ## under the pause button
const RING_R := 160.0
const ITEM_R := 44.0
const KEYS := [KEY_T, KEY_G, KEY_H]

var world: Node
var is_open := false
var _mine := {}                ## touch indices this node took
var _font: Font
var _list: Array = []

func _ready() -> void:
	name = "EmoteWheel"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = UiTheme.font(700)

func _touch() -> Control:
	return world.get("touch") if world else null

## The emote button, in this control's coordinates (just under the pause button).
func button_rect() -> Rect2:
	var t := _touch()
	if t == null: return Rect2()
	var pr: Rect2 = t.pause_rect()
	return Rect2(pr.get_center().x - BTN / 2.0, pr.end.y + GAP, BTN, BTN)

## The button shows (and works) while the touch layer does and the player can dance.
func shown() -> bool:
	var t := _touch()
	if t == null or not t.visible or t.spectate_mode: return false
	if world.paused or world.get("_results") != null or world.get("spectating") != null: return false
	var pv: Node = world.get("player_view")
	return pv != null and not pv.state.dead

func emotes() -> Array:
	return Save.wheel_emotes()

## Centres of the wheel items (screen middle, first at the top, clockwise).
func item_centers() -> Array:
	var out: Array = []
	var n := _list.size()
	var c := size / 2.0
	var r := minf(RING_R, size.y * 0.5 - ITEM_R - 30.0)
	for i in n:
		var a := -PI / 2.0 + TAU * i / maxf(n, 1)
		out.append(c + Vector2(cos(a), sin(a)) * r)
	return out

func open_wheel(on: bool) -> void:
	is_open = on and shown()
	_list = emotes() if is_open else []
	queue_redraw()

## Plays emote `id` on the player's wobbler (false when it cannot dance right now).
func play(id: String) -> bool:
	var pv: Node = world.get("player_view") if world else null
	var ok: bool = pv != null and pv.wobbler.play_emote(id)
	if ok:
		Sfx.play("boing")
		played.emit(id)
	open_wheel(false)
	return ok

func _item_at(p: Vector2) -> int:
	var cs := item_centers()
	for i in cs.size():
		if p.distance_to(cs[i]) <= ITEM_R + 6.0: return i
	return -1

## A press at `p`: on the button it toggles the wheel; with the wheel open it picks an emote or closes it.
## Returns true when this node used the press.
func press(p: Vector2) -> bool:
	if is_open:
		var i := _item_at(p)
		if i >= 0: play(_list[i])
		else: open_wheel(false)
		return true
	if shown() and button_rect().grow(6.0).has_point(p):
		open_wheel(true)
		return true
	return false

func _input(e: InputEvent) -> void:
	if world == null: return
	if e is InputEventScreenTouch:
		var st := e as InputEventScreenTouch
		if st.pressed:
			if press((make_input_local(st) as InputEventScreenTouch).position):
				_mine[st.index] = true
				get_viewport().set_input_as_handled()
		elif _mine.has(st.index):
			_mine.erase(st.index)
			get_viewport().set_input_as_handled()
	elif e is InputEventScreenDrag and _mine.has((e as InputEventScreenDrag).index):
		get_viewport().set_input_as_handled()
	elif e is InputEventMouseButton and e.device != InputEvent.DEVICE_ID_EMULATION:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and (is_open or shown()):
			if press((make_input_local(mb) as InputEventMouseButton).position):
				get_viewport().set_input_as_handled()

func _unhandled_key_input(e: InputEvent) -> void:
	if world == null or not (e is InputEventKey) or not e.pressed or e.echo: return
	var i := KEYS.find((e as InputEventKey).physical_keycode)
	if i < 0 or world.paused or world.get("_results") != null: return
	var s: Variant = Save.slots[i]
	if s != null:
		play(str(s))
		get_viewport().set_input_as_handled()

func _process(_dt: float) -> void:
	if is_open and not shown(): open_wheel(false)
	var vis := shown()
	if vis != visible: visible = vis
	if vis: queue_redraw()

func _draw() -> void:
	if not shown(): return
	var r := button_rect()
	var c := r.get_center()
	var op := float(_touch().get("opacity")) if _touch().get("opacity") != null else 0.85
	draw_circle(c, BTN / 2.0 + 2.0, Color(1, 1, 1, 0.35 * op))
	draw_circle(c, BTN / 2.0, Color(UiTheme.INK, 0.72 * op))
	_face(c, BTN * 0.3, Color(UiTheme.ACCENT, op))
	if not is_open: return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.38))
	var cs := item_centers()
	var mid := size / 2.0
	draw_circle(mid, 30.0, Color(UiTheme.INK, 0.9))
	var k := 9.0
	draw_line(mid + Vector2(-k, -k), mid + Vector2(k, k), Color.WHITE, 4.0, true)
	draw_line(mid + Vector2(-k, k), mid + Vector2(k, -k), Color.WHITE, 4.0, true)
	for i in cs.size():
		var id: String = _list[i]
		var p: Vector2 = cs[i]
		var rc := LockerData.rarity_color(LockerData.emote_rarity(id))
		draw_circle(p, ITEM_R + 3.0, rc)
		draw_circle(p, ITEM_R, Color(UiTheme.PANEL_SOLID, 0.95))
		EmoteIcon.paint(self, id, p, ITEM_R * 0.55, Color.WHITE)   # vector glyph (emoji fonts are not bundled)
		var nm := tr(LockerData.emote_name(id))
		var nw := _font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
		var np := p + Vector2(-nw / 2.0, ITEM_R + 20.0)
		draw_string_outline(_font, np, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, 6, Color(UiTheme.INK, 0.9))
		draw_string(_font, np, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color.WHITE)
		if i < 3 and Save.slots[i] == id:              # keyboard hint for the slots
			draw_string(_font, p + Vector2(ITEM_R * 0.55, -ITEM_R * 0.55), ["T", "G", "H"][i], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UiTheme.ACCENT)

func _face(c: Vector2, r: float, col: Color) -> void:
	draw_arc(c, r, 0.0, TAU, 24, col, 3.0, true)
	draw_circle(c + Vector2(-r * 0.36, -r * 0.25), r * 0.13, col)
	draw_circle(c + Vector2(r * 0.36, -r * 0.25), r * 0.13, col)
	draw_arc(c + Vector2(0, r * 0.05), r * 0.52, 0.35, PI - 0.35, 12, col, 3.0, true)
