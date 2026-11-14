class_name PerfOverlay
extends CanvasLayer
## Performance readout for testing on a device (Settings > Graphics > Performance readout, default off; docs/GRAPHICS.md
## "Measuring on device"). Four small lines in the top-left corner, under the HUD's score panel, refreshed once a
## second: fps and frame ms (avg / p95), CPU and GPU ms, draw calls and objects, tier / thermal / memory. A last line
## shows the actions each input source holds right now, so a stuck touch control (FIRE still down after the finger
## lifted) is visible on device. The node only exists while the setting is on (ui/fps_overlay.gd adds and frees it), so
## it costs nothing when off. The soak run (world/soak_run.gd) makes its own and listens to `sampled`; `extra` is an
## extra line before the held-actions one it uses for progress.

signal sampled(row: Dictionary)

var probe := PerfProbe.new()
var panel: PanelContainer
var label: Label
var extra := ""                  ## optional extra line (soak progress)
var map_name := ""               ## copied into each row
var last := {}                   ## the latest row
var _t := 0.0
var _hud: Control = null
var _inp: Node = null            ## the running match's PlayerInput, found once for the held-actions line

func _ready() -> void:
	layer = 119                  # under the FPS pill (120)
	process_mode = Node.PROCESS_MODE_ALWAYS
	panel = PanelContainer.new()
	panel.name = "Panel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.09, 0.11, 0.7)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 8; sb.content_margin_right = 8; sb.content_margin_top = 3; sb.content_margin_bottom = 3
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)
	label = Label.new()
	label.name = "Text"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.85, 0.95, 0.95))
	label.add_theme_constant_override("line_spacing", -2)
	label.text = tr("measuring…")
	panel.add_child(label)
	probe.begin(get_tree().root)
	place()

func _exit_tree() -> void:
	probe.end()

func _process(dt: float) -> void:
	_t += dt
	probe.add_frame(dt)
	if probe.secs < 1.0: return
	last = probe.take(_t, map_name)
	label.text = format(last, extra, held_line())
	place()
	sampled.emit(last)

## The last line of the readout: the actions held right now per input source, so a stuck control shows on device.
## Cheap and safe with no match running: the world's PlayerInput is found once, then only re-checked for validity.
func held_line() -> String:
	if _inp != null and not is_instance_valid(_inp):
		_inp = null
	if _inp == null:
		var found := get_tree().root.find_children("*", "PlayerInput", true, false)
		_inp = found[0] if not found.is_empty() else null
	var held := "none"
	if _inp != null:
		var st = _inp.get("state")
		if st != null:
			var r: String = st.held_report()
			if r != "":
				held = r
	return "held: " + held

## The readout text for a row (static so the test and the docs can show it). `held` is the held-actions line from
## held_line(); pass it to append it last (static callers without it keep the four/five-line text).
static func format(r: Dictionary, extra_line := "", held := "") -> String:
	if r.is_empty(): return ""
	var gpu := ("%.1f" % r["gpu_ms"]) if float(r["gpu_ms"]) >= 0.0 else "n/a"
	var objs := int(r["objects"])
	var t := "%d fps  %.1f ms  p95 %.1f\nCPU %.1f  GPU %s ms\n%d draws  %s obj\n%s  thermal %s  %d MB" % [
		int(round(r["fps"])), r["frame_ms_avg"], r["frame_ms_p95"], r["cpu_ms"], gpu, int(r["draws"]),
		("%.1fk" % (objs / 1000.0)) if objs >= 1000 else str(objs), r["tier"], r["thermal"], int(round(r["mem_mb"]))]
	if extra_line != "": t += "\n" + extra_line
	if held != "": t += "\n" + held
	return t

func rect() -> Rect2:
	return Rect2(panel.position, panel.size)

## Top-left corner of the safe area, or just under the HUD's score panel when a match is on (nothing else lives there).
func place() -> void:
	panel.reset_size()
	var ins: Array = SafeArea.insets(get_viewport())
	var pos := Vector2(float(ins[0]) + 4.0, float(ins[1]) + 4.0)
	if _hud == null or not is_instance_valid(_hud):
		var found := get_tree().root.find_children("*", "MatchHud", true, false)
		_hud = found[0] if not found.is_empty() else null
	if _hud != null and _hud.is_visible_in_tree() and _hud.has_node("Score"):
		var s: Control = _hud.get_node("Score")
		pos = Vector2(s.position.x, s.position.y + s.size.y * s.scale.y + 6.0)
	var fps := get_tree().root.get_node_or_null("FpsOverlay")
	if fps != null and fps.visible and fps.has_method("rect"):
		var r: Rect2 = fps.rect()
		if r.has_area():
			pos.y = maxf(pos.y, r.end.y + 4.0)
	panel.position = pos
