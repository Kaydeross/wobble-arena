class_name ControlsHelp
extends UiPage
## "Controls": one screen with a picture of the touch layout (the real TouchControls positions, mirrored when
## left-handed) and what each part does: the move stick, drag to look, double-tap to aim, FIRE, JUMP, MELEE (tap =
## shove, hold = kick), the context button (dash / reload), hotbar taps, pause and the emote button. A line under it
## lists the keyboard and controller keys. Opened from the pause menu and from Settings > Controls.

const KEYS := "Keyboard: WASD move · mouse look · click fire · right-click aim · Space jump · E shove · F kick · Q quick melee · 1-3 weapons · T G H emotes · Esc pause.   Controller: sticks move and look · RT fire · LT aim · A jump · RB shove · B kick · Start pause."

var pic: Control
var keys_l: Label

func _init() -> void:
	super._init()
	name = "ControlsHelp"

func _ready() -> void:
	build_frame("Controls")
	pic = Picture.new()
	pic.name = "Picture"
	pic.size_flags_vertical = SIZE_EXPAND_FILL
	pic.custom_minimum_size = Vector2(0, 220)
	col.add_child(pic)
	keys_l = Label.new()
	keys_l.name = "Keys"
	keys_l.text = KEYS
	keys_l.theme_type_variation = &"MutedLabel"
	keys_l.add_theme_font_size_override("font_size", 15)
	keys_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	keys_l.custom_minimum_size = Vector2(200, 0)
	col.add_child(keys_l)
	Settings.changed.connect(func(k: String, _v: Variant) -> void: if k == "touch_lefty": pic.queue_redraw())
	super._ready()

## The phone picture: a screen outline at the canvas aspect, the controls where TouchControls puts them, labels.
class Picture extends Control:
	const VS := Vector2(1170, 540)          ## the canvas the touch layer lays out on
	var font: Font
	var _sr := Rect2()

	func _ready() -> void:
		font = UiTheme.font(600)
		resized.connect(queue_redraw)

	## Screen rect inside this control (letterboxed at the canvas aspect).
	func screen() -> Rect2:
		var k := minf(size.x / VS.x, size.y / VS.y)
		var s := VS * k
		return Rect2((size - s) * 0.5, s)

	## Canvas point -> picture point (mirrored when left-handed).
	func _p(sr: Rect2, v: Vector2) -> Vector2:
		var x := v.x
		if bool(Settings.get_value("touch_lefty", false)): x = VS.x - x
		return sr.position + Vector2(x, v.y) * (sr.size.x / VS.x)

	func _btn(b: Array) -> Array:
		var u := TouchControls.UNIT
		var sz: float = float(b[3]) * u
		return [Vector2(VS.x - float(b[4]) * u - sz / 2.0, VS.y - float(b[5]) * u - sz / 2.0), sz / 2.0]

	func _draw() -> void:
		var sr := screen()
		var k := sr.size.x / VS.x
		draw_style_box(UiTheme.box(Color(0.02, 0.07, 0.09, 1.0), 26, Color(1, 1, 1, 0.25), 3), sr.grow(6))
		var mid := sr.position.x + sr.size.x * 0.45
		draw_line(Vector2(mid, sr.position.y + 12), Vector2(mid, sr.end.y - 12), Color(1, 1, 1, 0.12), 2.0)
		var fs := clampi(int(26.0 * k), 12, 26)
		var fs2 := clampi(int(20.0 * k), 11, 20)
		var lefty := bool(Settings.get_value("touch_lefty", false))
		var u := TouchControls.UNIT
		var labels: Array = []   ## [anchor point, side (-1 left of it, 1 right), title, sub]
		# move stick
		var sh := Vector2(TouchControls.STICK_R * u + 40.0 * u, VS.y - TouchControls.STICK_R * u - 34.0 * u)
		var sc := _p(sr, sh)
		draw_circle(sc, TouchControls.STICK_R * u * k, Color(1, 1, 1, 0.12))
		draw_arc(sc, TouchControls.STICK_R * u * k, 0, TAU, 40, Color(1, 1, 1, 0.5), 2.0, true)
		draw_circle(sc, TouchControls.STICK_R * u * k * 0.45, Color(1, 1, 1, 0.55))
		labels.append([sc + Vector2(0, -TouchControls.STICK_R * u * k - 8), 0, "Move", "Drag anywhere on the left side"])
		# look area
		var lc := _p(sr, Vector2(VS.x * 0.6, VS.y * 0.33))
		_arrows(lc, 60.0 * k)
		labels.append([lc + Vector2(0, 60.0 * k + fs * 1.2), 0, "Look", "Drag on the right side · double-tap to aim"])
		# action buttons
		var cols := {"fire": UiTheme.ACCENT, "jump": Color(0.22, 0.71, 0.66), "melee": Color(0.94, 0.45, 0.35), "context": Color(1, 1, 1, 0.6)}
		var words := {"fire": ["Fire: hold", ""], "jump": ["Jump", ""], "melee": ["Melee", "Tap: shove · hold: kick"], "context": ["Dash / Reload", ""]}
		var place := {"fire": 2, "jump": -1, "melee": 0, "context": -1}   ## where each label goes: below, left, above
		for b: Array in TouchControls.BUTTONS:
			var br := _btn(b)
			var c := _p(sr, br[0])
			var r: float = br[1] * k
			var col: Color = cols[b[0]]
			if b[0] == "context":
				draw_arc(c, r, 0, TAU, 36, col, 2.0, true)
			else:
				draw_circle(c, r, Color(col.r, col.g, col.b, 0.85))
			var side: int = place[b[0]]
			if lefty and absi(side) == 1: side = -side
			var off := Vector2(side * (r + 6), 0) if absi(side) == 1 else Vector2(0, -r - 4) if side == 0 else Vector2(0, r + 4)
			labels.append([c + off, side, words[b[0]][0], words[b[0]][1]])
		# pause + emote buttons (top corner)
		var ps := TouchControls.PAUSE_SIZE * u
		var pc := _p(sr, Vector2(VS.x - 8.0 * u - ps / 2.0, 6.0 * u + ps / 2.0))
		draw_rect(Rect2(pc - Vector2(ps, ps) * k * 0.5, Vector2(ps, ps) * k), Color(1, 1, 1, 0.25), true)
		draw_rect(Rect2(pc + Vector2(-ps * 0.18, -ps * 0.22) * k, Vector2(ps * 0.12, ps * 0.44) * k), Color.WHITE, true)
		draw_rect(Rect2(pc + Vector2(ps * 0.06, -ps * 0.22) * k, Vector2(ps * 0.12, ps * 0.44) * k), Color.WHITE, true)
		var side2 := -1 if not lefty else 1
		labels.append([pc + Vector2(side2 * (ps * k * 0.5 + 6), 0), side2, "Pause", ""])
		var ec := pc + Vector2(0, ps * k * 1.35)
		draw_circle(ec, ps * k * 0.42, Color(1, 1, 1, 0.25))
		draw_circle(ec + Vector2(-ps * 0.13, -ps * 0.08) * k, ps * 0.05 * k, Color.WHITE)
		draw_circle(ec + Vector2(ps * 0.13, -ps * 0.08) * k, ps * 0.05 * k, Color.WHITE)
		draw_arc(ec + Vector2(0, ps * 0.02) * k, ps * 0.2 * k, 0.3, PI - 0.3, 12, Color.WHITE, 2.0, true)
		labels.append([ec + Vector2(side2 * (ps * k * 0.5 + 6), 0), side2, "Emotes", ""])
		# hotbar
		var hw := 78.0
		var hc := sr.position + Vector2(sr.size.x * 0.5, sr.size.y - 46.0 * k)
		for i in 3:
			var rr := Rect2(hc + Vector2((i - 1.5) * (hw + 8) * k, -hw * 0.5 * k), Vector2(hw, hw) * k)
			draw_style_box(UiTheme.box(Color(1, 1, 1, 0.12 if i else 0.3), int(10 * k), Color(1, 1, 1, 0.4), 2), rr)
		labels.append([hc + Vector2(0, -hw * 0.5 * k - 6), 0, "Weapons", "Tap a slot to switch"])
		_sr = sr
		for l: Array in labels: _label(l[0], int(l[1]), str(l[2]), str(l[3]), fs, fs2)

	func _arrows(c: Vector2, r: float) -> void:
		var col := Color(1, 1, 1, 0.55)
		for d: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			var tip := c + d * r
			draw_line(c + d * r * 0.3, tip, col, 3.0, true)
			var n := Vector2(-d.y, d.x)
			draw_line(tip, tip - d * r * 0.25 + n * r * 0.18, col, 3.0, true)
			draw_line(tip, tip - d * r * 0.25 - n * r * 0.18, col, 3.0, true)

	## A title (and a smaller sub line) next to `at`: side -1 = to its left, 1 = to its right, 0 = centred above,
	## 2 = centred below; kept inside the screen picture.
	func _label(at: Vector2, side: int, title: String, sub: String, fs: int, fs2: int) -> void:
		title = tr(title)   # drawn with draw_string, so it does not translate itself
		sub = tr(sub)
		var w1 := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var w2 := font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2).x if sub != "" else 0.0
		var h := fs + (fs2 + 2 if sub != "" else 0)
		var y0 := at.y - h * 0.5 if absi(side) == 1 else at.y - h if side == 0 else at.y
		for i in 2:
			var t := title if i == 0 else sub
			if t == "": continue
			var f := fs if i == 0 else fs2
			var w := w1 if i == 0 else w2
			var x := at.x - w if side == -1 else at.x if side == 1 else at.x - w * 0.5
			x = clampf(x, _sr.position.x + 6.0, maxf(_sr.position.x + 6.0, _sr.end.x - w - 6.0))
			var y := y0 + f * 0.8 + (0.0 if i == 0 else fs + 2.0)
			draw_string_outline(font, Vector2(x, y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, f, 5, Color(0, 0, 0, 0.75))
			draw_string(font, Vector2(x, y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, f, Color.WHITE if i == 0 else UiTheme.MUTED)
