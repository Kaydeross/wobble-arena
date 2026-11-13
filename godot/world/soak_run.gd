class_name SoakRun
extends Node
## The 15-minute soak test (Settings > Graphics > 15-minute soak test; docs/GRAPHICS.md "Measuring on device"). Child of
## a World that was built with `soak_duration > 0`: an offline Chaos 5v5 (10 fighters, random floor events, no K.O. limit)
## on the big arenas in turn (a third of the time each), the player a scripted bot that wanders, fires and jumps.
## Once a second the on-screen readout (ui/perf_overlay.gd) hands over a row; it goes to user://soak/<date>.csv
## (columns: logic/perf_stats.gd). At the end the match stops, the CSV gets a .txt summary next to it and a card shows the
## numbers with Copy summary and Back to title. The screen is kept awake for the run. It only reads timings: the sim,
## combat and physics play exactly as in a normal match. Pausing (the pause menu) stops the clock.

const DURATION := 900.0
const MAPS := ["arenaxl", "colosseum", "farm"]    ## Chaos maps (ModeRules.CHAOS_MAPS), the biggest first
const MODE := "chaos"
const DIR := "user://soak"
const SEED := 20250611                            ## the same match every run, so two runs compare
const FILES_HINT := "Files app > On My iPhone > Wobblers Arena > soak"

signal finished(summary: Dictionary)

var world: Node
var duration := DURATION
var maps: Array = MAPS
var dir := DIR
var rows: Array = []
var elapsed := 0.0
var segment := 0
var done := false
var summary := {}
var csv_path := ""
var txt_path := ""
var text := ""                    ## the summary as plain text (after the run)
var overlay: PerfOverlay
var card: Control = null
var _file: FileAccess = null
var _layer: CanvasLayer = null

## A world set up for a soak run, ready to be added to the tree (or handed to change_scene_to_node).
static func make_world(p_duration := DURATION, p_maps: Array = MAPS, p_dir := DIR) -> Node:
	var w: Node = load("res://world/world.tscn").instantiate()
	w.map_id = p_maps[0]
	w.mode_id = MODE
	w.ko_limit = 0
	w.bot_count = 9
	w.difficulty = "normal"
	w.rng_seed = SEED
	w.soak_duration = p_duration
	w.soak_maps = p_maps.duplicate()
	w.soak_dir = p_dir
	return w

## Starts a soak run from a menu: replaces the current scene.
static func launch(tree: SceneTree) -> void:
	tree.change_scene_to_node(make_world())

func _ready() -> void:
	world = get_parent()
	duration = float(world.soak_duration)
	if not (world.soak_maps as Array).is_empty(): maps = world.soak_maps
	if world.soak_dir != "": dir = world.soak_dir
	DirAccess.make_dir_recursive_absolute(dir)
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	csv_path = "%s/%s.csv" % [dir, stamp]
	_file = FileAccess.open(csv_path, FileAccess.WRITE)
	if _file: _file.store_line(PerfStats.csv_header())
	DisplayServer.screen_set_keep_on(true)
	overlay = PerfOverlay.new()
	overlay.map_name = world.map_id
	overlay.extra = tr("Soak 0:00 / %s") % PerfStats.mmss(duration)
	overlay.sampled.connect(_on_sample)
	add_child(overlay)

func _exit_tree() -> void:
	DisplayServer.screen_set_keep_on(false)
	if _file: _file.close(); _file = null
	if is_inside_tree() and get_tree().root.disable_3d: get_tree().root.disable_3d = false

func _process(dt: float) -> void:
	if done or world.sim == null: return
	if world.paused:
		_stop_input()
		return
	elapsed += dt
	_drive()
	if elapsed >= duration:
		_finish()
		return
	var want := mini(int(elapsed / (duration / maps.size())), maps.size() - 1)
	if want != segment:
		segment = want
		_load(maps[want])
	elif world.sim.combat.rules.match_over or world.get("_results") != null:
		_load(maps[segment])        # a match that ended on its own starts again; the clock runs on

func _load(id: String) -> void:
	world.load_map(id)
	overlay.map_name = id

## The player bot: wanders in a slow loop, fires in bursts, jumps now and then.
func _drive() -> void:
	var st: InputState = world.input.state
	var a := elapsed * 0.7
	st.set_move("script", Vector2(sin(a), cos(a * 0.5)))
	st.hold("script", "fire", fmod(elapsed, 3.0) < 1.5)
	if fmod(elapsed, 4.0) < get_process_delta_time(): st.press("jump")

func _stop_input() -> void:
	var st: InputState = world.input.state
	st.set_move("script", Vector2.ZERO)
	st.hold("script", "fire", false)

func _on_sample(row: Dictionary) -> void:
	if done or world.paused or row.is_empty(): return
	row["t"] = snappedf(elapsed, 0.1)
	row["map"] = world.map_id
	rows.append(row)
	if _file:
		_file.store_line(PerfStats.csv_line(row))
		_file.flush()
	overlay.extra = tr("Soak %s / %s") % [PerfStats.mmss(elapsed), PerfStats.mmss(duration)]

func meta() -> Dictionary:
	return {"device": "%s, %s %s" % [OS.get_model_name(), OS.get_name(), OS.get_version()], "build": load("res://ui/settings_screen.gd").version_text(),
		"renderer": RenderingServer.get_current_rendering_method(), "csv": csv_path.get_file()}

func _finish() -> void:
	done = true
	_stop_input()
	if _file: _file.close(); _file = null
	summary = PerfStats.summarize(rows)
	text = PerfStats.summary_text(summary, meta())
	txt_path = csv_path.get_basename() + ".txt"
	var f := FileAccess.open(txt_path, FileAccess.WRITE)
	if f: f.store_string(text + "\n"); f.close()
	DisplayServer.screen_set_keep_on(false)
	overlay.queue_free()
	world.auto_run = false                 # the match stops; nothing but the card renders
	(world.get_node("UI") as CanvasLayer).visible = false
	get_tree().root.disable_3d = true
	_show_card()
	finished.emit(summary)

func stat_pairs() -> Array:
	var s := summary
	var thermal := tr("%d change(s)") % s["thermal_changes"] if s["thermal_known"] else tr("n/a (no iOS API)")
	var gpu := ("%.1f" % s["gpu_ms"]) if float(s["gpu_ms"]) >= 0.0 else "n/a"
	return [[tr("Average fps"), "%.1f" % s["avg_fps"]],
		[tr("Frames over %.1f ms") % PerfStats.SLOW_MS, "%.1f %%" % s["slow_pct"]],
		[tr("Worst minute"), "#%d, %.1f fps" % [s["worst_minute"], s["worst_minute_fps"]]],
		[tr("Frame p95 (mean / worst)"), "%.1f / %.1f ms" % [s["p95_mean"], s["p95_worst"]]],
		[tr("fps first / last third"), "%.1f / %.1f" % [s["first_third_fps"], s["last_third_fps"]]],
		[tr("Thermal state"), thermal],
		[tr("CPU / GPU ms (median)"), "%.1f / %s" % [s["cpu_ms"], gpu]],
		[tr("Length"), PerfStats.mmss(float(s["seconds"]))]]

func _show_card() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 130
	add_child(_layer)
	card = Control.new()
	card.name = "SoakCard"
	card.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(card)
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.1, 0.13, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	card.add_child(bg)
	var ins: Array = SafeArea.insets(card.get_viewport())
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.add_theme_constant_override("margin_left", int(ins[0]) + 24)
	m.add_theme_constant_override("margin_top", int(ins[1]) + 12)
	m.add_theme_constant_override("margin_right", int(ins[2]) + 24)
	m.add_theme_constant_override("margin_bottom", int(ins[3]) + 12)
	card.add_child(m)
	var v := VBoxContainer.new()
	v.name = "Box"
	v.add_theme_constant_override("separation", 8)
	m.add_child(v)
	var pass_: bool = summary["verdict"] == "PASS"
	var title := Label.new()
	title.name = "Title"
	title.theme_type_variation = &"TitleLabel"
	title.add_theme_color_override("font_color", Color(0.55, 0.9, 0.55) if pass_ else Color(1.0, 0.6, 0.5))
	title.text = tr("Soak test: %s") % tr(summary["verdict"])
	v.add_child(title)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 6)
	sc.add_child(inner)
	var g := GridContainer.new()
	g.name = "Stats"
	g.columns = 4
	g.add_theme_constant_override("h_separation", 18)
	g.add_theme_constant_override("v_separation", 4)
	inner.add_child(g)
	for p: Array in stat_pairs():
		var k := Label.new(); k.text = p[0]; k.theme_type_variation = &"MutedLabel"; k.add_theme_font_size_override("font_size", 18)
		var val := Label.new(); val.text = p[1]; val.add_theme_font_size_override("font_size", 22)
		val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		g.add_child(k); g.add_child(val)
	for r: String in summary["reasons"]:
		var l := Label.new(); l.text = "• " + r; l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_font_size_override("font_size", 16); l.add_theme_color_override("font_color", Color(1.0, 0.7, 0.6))
		inner.add_child(l)
	var path := Label.new()
	path.name = "Saved"
	path.theme_type_variation = &"MutedLabel"
	path.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	path.add_theme_font_size_override("font_size", 14)
	path.text = tr("Saved %s (and .txt). %s") % [csv_path.get_file(), tr(FILES_HINT)]
	inner.add_child(path)
	var bar := HBoxContainer.new()
	bar.name = "Buttons"
	bar.add_theme_constant_override("separation", 12)
	v.add_child(bar)
	var copy := Button.new()
	copy.name = "Copy"
	copy.text = tr("Copy summary")
	copy.custom_minimum_size = Vector2(0, 58)
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_font_size_override("font_size", 20)
	copy.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(text)
		copy.text = tr("Copied"))
	bar.add_child(copy)
	var back := Button.new()
	back.name = "Back"
	back.text = tr("Back to title")
	back.theme_type_variation = &"PrimaryButton"
	back.custom_minimum_size = Vector2(0, 58)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.add_theme_font_size_override("font_size", 20)
	back.pressed.connect(func() -> void:
		get_tree().root.disable_3d = false
		get_tree().change_scene_to_file("res://scenes/main.tscn"))
	bar.add_child(back)
