class_name PingBadge
extends HBoxContainer
## The online status chip: a latency dot + "Room 4821 · 34 ms" ("Room 4821 · Host · 34 ms" for the host). Hidden offline
## (no session). Green <= GOOD ms, amber up to OK, coral above, grey while the ping is unknown (< 0, the "ms" part is
## then left out). The HUD owns one (hud.gd `_build_net`, named NetStatus, under the K.O. panel in the safe area) and
## calls refresh(world.session) every frame; nothing here talks to the network. Both GuestSession and HostSession
## (a relay ping every 1.5 s, host_session.gd poll) fill `ping_ms`.

const GOOD := 60       ## ms: up to and including this the dot is green
const OK := 140        ## ms: up to and including this amber, above coral

var dot: ColorRect
var label: Label

func _init() -> void:
	name = "NetStatus"
	add_theme_constant_override("separation", 5)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	modulate.a = 0.75
	visible = false
	dot = ColorRect.new()
	dot.custom_minimum_size = Vector2(8, 8)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dot)
	label = Label.new()
	label.theme_type_variation = &"HudLabel"
	label.add_theme_font_size_override("font_size", UiTheme.MIN_FONT)
	label.add_theme_color_override("font_color", UiTheme.MUTED)
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_color_override("font_outline_color", UiTheme.INK)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)

static func color_for(ms: int) -> Color:
	if ms < 0: return UiTheme.MUTED
	if ms <= GOOD: return Color("5fd97a")
	if ms <= OK: return Color("f2b53c")
	return Color("ef5b5b")

## What the chip says for a room code, host flag and ping (tests too).
static func text_for(room: String, is_host: bool, ms: int) -> String:
	var txt := TranslationServer.translate("Room %s") % room
	if is_host: txt += " · " + TranslationServer.translate("Host")
	if ms >= 0: txt += " · %d ms" % ms
	return txt

## Show / hide and update from a GuestSession or HostSession (null = offline: hidden).
func refresh(s: Variant) -> void:
	visible = s != null
	if s == null: return
	var txt := text_for(str(s.room_code), s.is_host(), int(s.ping_ms))
	if label.text != txt: label.text = txt
	dot.color = color_for(int(s.ping_ms))
	reset_size()

func text() -> String:
	return label.text
