extends Control
## HUD hotbar (bottom centre): slots 1-3 and the spatula (Q), the active slot raised with a yellow glow, ammo,
## a reload progress strip, the weapon name shrunk to fit (never clipped) and keybind badges that hide while the
## last input was touch. `slots` is filled by hud.gd from the player's FighterState each frame. On touch screens the
## touch layer (input/touch_controls.gd) makes the slots tappable through slot_rect().

const SLOT := Vector2(104, 66)
const GAP := 8.0
const KEYS := ["1", "2", "3", "Q"]

var slots: Array = []          ## 4 x {name, ammo, empty, active, reload (0..1 or -1)}
var show_keys := true
var _glow := [0.0, 0.0, 0.0, 0.0]
var _font: Font

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = UiTheme.font(700)
	custom_minimum_size = Vector2(SLOT.x * 4 + GAP * 3, SLOT.y + 8)
	size = custom_minimum_size

## Slot i (0..3) in local coordinates, including the space the active slot rises into (touch hit area).
func slot_rect(i: int) -> Rect2:
	return Rect2(Vector2(i * (SLOT.x + GAP), 2), Vector2(SLOT.x, SLOT.y + 6))

func tick(dt: float) -> void:
	for i in mini(slots.size(), 4):
		var on: bool = slots[i]["active"]
		_glow[i] = move_toward(_glow[i], 1.0 if on else 0.0, dt * 8.0)
	queue_redraw()

## Largest font size (<= start) at which `t` fits in `w`.
func _fit(t: String, w: float, start: int) -> int:
	var fs := start
	while fs > 10 and _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > w:
		fs -= 1
	return fs

func _draw() -> void:
	for i in mini(slots.size(), 4):
		var s: Dictionary = slots[i]
		var g: float = _glow[i]
		var r := Rect2(Vector2(i * (SLOT.x + GAP), 8 - 6 * g), SLOT)
		var empty: bool = s["empty"]
		var bg := Color(UiTheme.PANEL.r, UiTheme.PANEL.g, UiTheme.PANEL.b, 0.5 if empty else 0.8)
		if g > 0.0: bg = bg.lerp(Color(0.13, 0.36, 0.4, 0.92), g)
		var sb := UiTheme.box(bg, 14, Color(1, 1, 1, 0.12 if empty else 0.2).lerp(UiTheme.ACCENT, g), 2 + int(round(g)), 4)
		if g > 0.0:
			sb.shadow_color = Color(UiTheme.ACCENT.r, UiTheme.ACCENT.g, UiTheme.ACCENT.b, 0.45 * g)
			sb.shadow_size = int(12 * g)
			sb.shadow_offset = Vector2.ZERO
		draw_style_box(sb, r)
		var name: String = s["name"]
		var fs := _fit(name, SLOT.x - 14, 19)
		var tw := _font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var tc := Color(1, 1, 1, 0.4) if empty else Color.WHITE
		var tp := Vector2(r.position.x + (SLOT.x - tw) / 2.0, r.end.y - 13)
		if not empty:
			draw_string_outline(_font, tp, name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.35))
		draw_string(_font, tp, name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, tc)
		var ammo: String = s["ammo"]
		if ammo != "":
			var sub: String = s.get("sub", "")
			var low: bool = s.get("low", false)
			var afs := 30 if g > 0.5 else 24                               # the number that matters is big and easy to read
			var main_c := Color(1.0, 0.42, 0.36) if low else (Color.WHITE if g > 0.5 else Color(1, 1, 1, 0.75))
			var aw := _font.get_string_size(ammo, HORIZONTAL_ALIGNMENT_LEFT, -1, afs).x
			var sw := _font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x if sub != "" else 0.0
			var ax := r.end.x - 9 - aw - sw
			var ay := r.position.y + 31
			draw_string_outline(_font, Vector2(ax, ay), ammo, HORIZONTAL_ALIGNMENT_LEFT, -1, afs, 5, Color(0, 0, 0, 0.5))
			draw_string(_font, Vector2(ax, ay), ammo, HORIZONTAL_ALIGNMENT_LEFT, -1, afs, main_c)
			if sub != "":
				draw_string(_font, Vector2(ax + aw + 1, ay), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UiTheme.MUTED)
		var rl: float = s["reload"]
		if rl >= 0.0:
			var bar := Rect2(r.position + Vector2(10, SLOT.y - 8), Vector2((SLOT.x - 20), 4))
			draw_rect(bar, Color(0, 0, 0, 0.5))
			draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(rl, 0, 1), bar.size.y)), UiTheme.ACCENT)
		if show_keys:
			var kb := Rect2(r.position + Vector2(7, 7), Vector2(20, 20))
			var ks := UiTheme.box(UiTheme.ACCENT if g > 0.5 else Color(1, 1, 1, 0.85), 6, Color(0, 0, 0, 0), 0, 0)
			draw_style_box(ks, kb)
			var kw := _font.get_string_size(KEYS[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
			draw_string(_font, kb.position + Vector2((20 - kw) / 2.0, 15.5), KEYS[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UiTheme.INK)
