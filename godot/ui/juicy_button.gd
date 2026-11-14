class_name JuicyButton
extends Node
## Button micro-interaction: a small scale bounce, a brightness shift and a soft click sound on hover and press (Tween).
## Add as a child of any BaseButton, or call JuicyButton.attach(button) / JuicyButton.attach_all(root).
## The press sound is the web engine's "click" (public/index.html SOUNDS, docs/AUDIO.md) at a deliberately low volume:
## UI feedback, not a hit. It never touches the button's signals or state.

const HOVER_SCALE := 1.04
const PRESS_SCALE := 0.94
const HOVER_BRIGHT := 1.12
const PRESS_BRIGHT := 0.9
const CLICK_VOL := 0.5

var _b: BaseButton
var _tw: Tween
var _hover := false

static func attach(b: BaseButton) -> JuicyButton:
	for c in b.get_children():
		if c is JuicyButton: return c
	var j := JuicyButton.new()
	j.name = "Juicy"
	b.add_child(j)
	return j

static func attach_all(root: Node) -> void:
	if root is BaseButton: attach(root)
	for c in root.get_children():
		if not c is JuicyButton: attach_all(c)

func _ready() -> void:
	_b = get_parent() as BaseButton
	if _b == null: return
	_b.resized.connect(_pivot)
	_b.mouse_entered.connect(func(): _hover = true; _to(HOVER_SCALE, HOVER_BRIGHT, 0.12))
	_b.mouse_exited.connect(func(): _hover = false; _to(1.0, 1.0, 0.16))
	_b.button_down.connect(func(): _to(PRESS_SCALE, PRESS_BRIGHT, 0.06); _click())
	_b.button_up.connect(_release)
	_pivot()

## A soft UI click on every press (the web game's `click`), skipped for disabled buttons. The sound is the only
## non-visual part: the scale / brightness tween still never touches the button's signals or state. The `Sfx` autoload
## is looked up through the tree instead of as a bare global: a test's main loop can pull this script in before the
## autoload globals are registered, where `Sfx.play(...)` would fail to compile (same as world/fx.gd).
func _click() -> void:
	if _b.disabled: return
	var sfx := get_node_or_null("/root/Sfx")
	if sfx: sfx.call("play", "click", CLICK_VOL)

func _pivot() -> void:
	_b.pivot_offset = _b.size / 2.0

func _release() -> void:
	# overshoot a little, then settle: the "bounce"
	_kill()
	var rest := HOVER_SCALE if _hover else 1.0
	_tw = _b.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tw.tween_property(_b, "scale", Vector2.ONE * (rest + 0.06), 0.08)
	var br := HOVER_BRIGHT if _hover else 1.0
	_tw.parallel().tween_property(_b, "self_modulate", Color(br, br, br, 1.0), 0.08)
	_tw.tween_property(_b, "scale", Vector2.ONE * rest, 0.22)

func _to(s: float, bright: float, t: float) -> void:
	if _b.disabled: return
	_kill()
	_tw = _b.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tw.tween_property(_b, "scale", Vector2.ONE * s, t)
	_tw.parallel().tween_property(_b, "self_modulate", Color(bright, bright, bright, 1.0), t)

func _kill() -> void:
	if _tw and _tw.is_valid(): _tw.kill()
