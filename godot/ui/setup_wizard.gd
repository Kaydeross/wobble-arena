class_name SetupWizard
extends VBoxContainer
## Offline match setup, one choice per page (title screen Play opens it):
##   1 Game type (cards for ModeRules.PLAYABLE + Construction, read from code, and the Moving floor row: Settings "dyn"),
##   2 Arena (cards for the maps that game type allows), 3 Players (you + 1..7 bots, team modes fix the count; bot
##   skill), 4 Character (Content.classes, real 3D renders of the Wobbler: ui/character_stage.gd), 5 Start (a summary
##   of the four picks, each row jumps back to its page, and the big Start button).
## Every pick is saved in Settings straight away (mode, offline_map, dyn, bots, difficulty, class), so the next Play
## starts where the last one ended. Game types restrict arenas: when the remembered arena is not allowed in the new
## game type, the wizard moves to the nearest allowed one and says so in one line (`note`).
## Card grids scroll with DragScroll (drag + fling, a tap picks, a drag never does; wheel on PC) inside a frame that
## fades the edge where more cards are hidden; opening a page scrolls its selected card into view.
## Built in code (no .tscn) in the UiTheme look; scenes/main.tscn adds it under Safe. Header: title + step + note;
## body: the page; footer: Back, the step pills (tap to jump) and Next / Start.

signal start_requested     ## Start on the last page
signal closed              ## Back on the first page

const TITLES := ["Pick a game type", "Pick an arena", "Players", "Pick your character", "Ready to play?"]
const SHORT := ["Game type", "Arena", "Players", "Character", "Start"]
const PAGE_NAMES := ["GameType", "Arena", "Players", "Character", "Start"]
enum {P_MODE, P_ARENA, P_PLAYERS, P_CHAR, P_START}
const BOT_MIN := 1
const BOT_MAX := 7
const DIFFS := ["easy", "normal", "hard", "insane"]
const GAP := 12
const MAP_CARD := Vector2(220, 140)
const MODE_CARD := Vector2(220, 104)
const CLASS_CARD := Vector2(172, 250)

var page := 0
var map_id := "arena"
var mode_id := "classic"
var dyn := "random"
var bots := 3
var diff := "normal"
var cls := "wobbler"
var note := ""              ## one line shown in the header (arena moved because of the game type, ...)
var _want_map := ""         ## the arena the player last tapped: a game type change returns to it when it is allowed again

var title_l: Label
var step_l: Label
var note_l: Label
var pages: Array = []       ## the five page Controls (only `page` is visible)
var back_b: Button
var next_b: Button
var step_bs: Array = []
var players_l: Label
var players_hint: Label
var stage: CharacterStage   ## the shared 3D stage for the character cards
var _grids := {}            ## page index -> [DragScroll, GridContainer, card width, EdgeFade]
var _map_bs := {}
var _mode_bs := {}
var _class_bs := {}
var _class_art := {}        ## class id -> TextureRect
var _dyn_bs := {}
var _bot_bs := {}
var _diff_bs := {}
var _sum_bs: Array = []
var _sum_vals: Array = []
var _styles := {}
var _loaded := false
static var _heavy: Font

# ---------------- choices ----------------

## Game types the wizard offers: every mode the port plays offline (ModeRules.PLAYABLE) plus Construction, in that order.
static func modes() -> Array:
	var out: Array = []
	for m: String in ModeRules.PLAYABLE + ["construction"]:
		if Content.modes.has(m) and not out.has(m): out.append(m)
	return out

## The arenas a mode allows (web `mapAllowed`): the mode's own list (ModeRules.maps_for) if it has one, else every
## map except the test level and maps that belong to another mode (`only`). The Practice Range goes last.
static func maps_for(mode: String) -> Array:
	var out: Array = []
	var fixed: Array = ModeRules.maps_for(mode)
	if fixed.size() > 0:
		for id: String in fixed:
			if Content.maps.has(id): out.append(id)
		return out
	for id: String in ModeRules.sort_maps(Content.maps.keys()):
		var m := Content.get_map(id)
		var only := str(m.get("only", ""))
		if id == "test" or id == "practice" or id == "custom" or str(m.get("cat", "")) == "sandbox": continue
		if only != "" and only != mode: continue
		out.append(id)
	if Content.maps.has("practice") and mode == "classic": out.append("practice")
	return out

## `want` if `valid` has it, else the valid map closest to it in the map list order.
static func nearest_map(want: String, valid: Array) -> String:
	if valid.is_empty() or valid.has(want): return want
	var order: Array = Content.maps.keys()
	var wi := order.find(want)
	var best: String = valid[0]
	if wi < 0: return best
	var bd := 1 << 30
	for id: String in valid:
		var d := absi(order.find(id) - wi)
		if d < bd: bd = d; best = id
	return best

## How many bots actually play (team modes fix it: ModeRules.bot_count).
func bot_total() -> int:
	return ModeRules.bot_count(mode_id, Content.modes, bots)

func is_team_mode() -> bool:
	return int(Content.modes.get(mode_id, {}).get("teams", 0)) > 0

## Team Deathmatch: the Players page sizes the two teams (odd bot counts only, so the sides stay even).
func is_flex_teams() -> bool:
	return is_team_mode() and bool(Content.modes.get(mode_id, {}).get("flexTeams", false))

static func mode_name(m: String) -> String:
	return str(Content.modes.get(m, {}).get("name", m.capitalize()))

static func map_name(id: String) -> String:
	return str(Content.get_map(id).get("name", id))

static func class_name_of(id: String) -> String:
	return str(Content.get_class_data(id).get("name", id))

## The last setup in one line (title screen Play tooltip).
func summary_line() -> String:
	return "%s · %s · %s" % [mode_name(mode_id), map_name(map_id), _players_text()]

func _players_text() -> String:
	var t := bot_total()
	if mode_id == "practice": return "You + %d dummies" % t
	return "You + %d bot%s" % [t, "" if t == 1 else "s"]

## Loads the remembered choices from Settings (and fixes anything no longer valid).
func load_settings() -> void:
	var ms := modes()
	mode_id = str(Settings.get_value("mode", "classic"))
	if not ms.has(mode_id): mode_id = "classic" if ms.has("classic") else ms[0]
	dyn = str(Settings.get_value("dyn", "random"))
	if not Dynamics.KINDS.has(dyn): dyn = "random"
	bots = clampi(int(Settings.get_value("bots", 3)), BOT_MIN, BOT_MAX)
	diff = str(Settings.get_value("difficulty", "normal"))
	if not DIFFS.has(diff): diff = "normal"
	cls = str(Settings.get_value("class", "wobbler"))
	if not Content.classes.has(cls): cls = Content.classes.keys()[0] if Content.classes.size() > 0 else "wobbler"
	_want_map = str(Settings.get_value("offline_map", "arena"))
	map_id = nearest_map(_want_map, maps_for(mode_id))
	note = ""
	_loaded = true
	_rebuild_maps()
	_refresh()

func set_map(id: String) -> void:
	map_id = id
	_want_map = id
	note = ""
	Settings.set_value("offline_map", id)
	_refresh()

## Picks a game type; when the arena is not allowed in it, moves to the nearest allowed arena and says so.
func set_mode(m: String) -> void:
	mode_id = m
	Settings.set_value("mode", m)
	var valid := maps_for(m)
	var want := _want_map if _want_map != "" else map_id
	var to := nearest_map(want, valid)
	note = ""
	if to != map_id and not valid.has(map_id):
		note = "%s has no %s: arena is now %s." % [mode_name(m), map_name(map_id), map_name(to)]
	elif to != map_id:
		note = "Arena back to %s." % map_name(to)
	map_id = to
	Settings.set_value("offline_map", to)
	_rebuild_maps()
	_refresh()

func set_dyn(k: String) -> void:
	dyn = k
	Settings.set_value("dyn", k)
	_refresh()

func set_bots(n: int) -> void:
	bots = clampi(n, BOT_MIN, BOT_MAX)
	Settings.set_value("bots", bots)
	_refresh()

func set_diff(d: String) -> void:
	diff = d
	Settings.set_value("difficulty", d)
	_refresh()

func set_class(id: String) -> void:
	cls = id
	Settings.set_value("class", id)
	_refresh()
	_show_class_art()

## Writes every choice (Start does this once more, so a match always starts from what is on screen).
func save() -> void:
	for kv in [["offline_map", map_id], ["mode", mode_id], ["dyn", dyn], ["bots", bots], ["difficulty", diff], ["class", cls]]:
		Settings.set_value(kv[0], kv[1])

# ---------------- navigation ----------------

func go(i: int) -> void:
	page = clampi(i, 0, pages.size() - 1)
	for k in pages.size():
		(pages[k] as Control).visible = k == page
	_refresh()
	if stage:
		stage.active = page == P_CHAR and is_visible_in_tree()
		if page == P_CHAR: _bake()
	_reveal_selected.call_deferred()
	if Tier.is_pc(): next_b.grab_focus.call_deferred()

func next() -> void:
	if page >= pages.size() - 1:
		save()
		start_requested.emit()
	else:
		go(page + 1)

func back() -> void:
	if page == 0: closed.emit()
	else: go(page - 1)

func _unhandled_input(e: InputEvent) -> void:
	if is_visible_in_tree() and e.is_action_pressed("ui_cancel"):
		back()
		get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and stage:
		stage.active = page == P_CHAR and is_visible_in_tree()

## The selected card of the current page, scrolled into view (after the grid has its layout).
func _reveal_selected() -> void:
	if not _grids.has(page) or not is_inside_tree(): return
	await get_tree().process_frame
	if not _grids.has(page): return
	var store: Dictionary = {P_MODE: _mode_bs, P_ARENA: _map_bs, P_CHAR: _class_bs}[page]
	var key: String = {P_MODE: mode_id, P_ARENA: map_id, P_CHAR: cls}[page]
	if store.has(key): (_grids[page][0] as DragScroll).reveal(store[key])

## The card currently picked on a grid page (tests).
func selected_card(p: int) -> Control:
	var store: Dictionary = {P_MODE: _mode_bs, P_ARENA: _map_bs, P_CHAR: _class_bs}.get(p, {})
	var key: String = {P_MODE: mode_id, P_ARENA: map_id, P_CHAR: cls}.get(p, "")
	return store.get(key)

func scroll_of(p: int) -> DragScroll:
	return _grids[p][0] if _grids.has(p) else null

# ---------------- build ----------------

func _init() -> void:
	name = "Wizard"
	add_theme_constant_override("separation", 10)
	size_flags_vertical = SIZE_EXPAND_FILL

func _ready() -> void:
	if _heavy == null: _heavy = UiTheme.font(700)
	_make_styles()
	if not _loaded: load_settings()
	stage = CharacterStage.new()
	add_child(stage)
	stage.baked_one.connect(func(_id: String) -> void: _show_class_art())
	_build_head()
	var body := VBoxContainer.new()
	body.name = "Pages"
	body.size_flags_vertical = SIZE_EXPAND_FILL
	add_child(body)
	for k in PAGE_NAMES.size():
		var p := VBoxContainer.new()
		p.name = PAGE_NAMES[k]
		p.size_flags_vertical = SIZE_EXPAND_FILL
		p.add_theme_constant_override("separation", 10)
		body.add_child(p)
		pages.append(p)
	_build_mode(pages[P_MODE])
	_build_arena(pages[P_ARENA])
	_build_players(pages[P_PLAYERS])
	_build_class(pages[P_CHAR])
	_build_start(pages[P_START])
	_build_foot()
	JuicyButton.attach_all(self)
	go(page)

func _bake() -> void:
	var ids: Array = Content.classes.keys()
	stage.live(cls)
	stage.bake(ids)
	_show_class_art()

## Character card art: the selected card shows the live (turning) stage, the others their baked render.
func _show_class_art() -> void:
	if stage == null: return
	stage.live(cls)
	for id: String in _class_art:
		var tr: TextureRect = _class_art[id]
		var tex: Texture2D = stage.get_texture() if id == cls and not stage.is_baking() else stage.baked.get(id)
		tr.texture = tex

func _make_styles() -> void:
	var edge := Color(1, 1, 1, 0.14)
	var n := UiTheme.box(UiTheme.PANEL_HI, 16, edge, 2, 4, 5)
	var h := UiTheme.box(UiTheme.PANEL_HI.lightened(0.08), 16, Color(1, 1, 1, 0.3), 2, 6, 5)
	var sel := UiTheme.box(Color(0.15, 0.33, 0.37, 0.96), 16, UiTheme.ACCENT, 3, 8, 6, UiTheme.ACCENT_DARK)
	sel.border_width_bottom = 6
	var d := UiTheme.box(Color(0.1, 0.2, 0.23, 0.5), 16, Color(1, 1, 1, 0.06), 2, 0, 3)
	var f := UiTheme.box(Color.TRANSPARENT, 19, Color.WHITE, 3, 0)
	f.draw_center = false
	f.expand_margin_left = 3; f.expand_margin_right = 3; f.expand_margin_top = 3; f.expand_margin_bottom = 3
	_styles = {"normal": n, "hover": h, "pressed": sel, "hover_pressed": sel, "disabled": d, "focus": f}

func _label(text: String, size: int, variation := "", clip := false) -> Label:
	var l := Label.new()
	l.text = text
	if variation != "": l.theme_type_variation = variation
	l.add_theme_font_size_override("font_size", size)
	if clip:
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _build_head() -> void:
	var head := HBoxContainer.new()
	head.name = "Head"
	head.add_theme_constant_override("separation", 14)
	add_child(head)
	title_l = _label("", 36, "TitleLabel")
	title_l.name = "Title"
	head.add_child(title_l)
	step_l = _label("", 18, "MutedLabel")
	step_l.name = "Step"
	step_l.size_flags_vertical = SIZE_SHRINK_CENTER
	head.add_child(step_l)
	note_l = _label("", 18, "", true)
	note_l.name = "Note"
	note_l.add_theme_color_override("font_color", UiTheme.ACCENT)
	note_l.size_flags_horizontal = SIZE_EXPAND_FILL
	note_l.size_flags_vertical = SIZE_SHRINK_CENTER
	note_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(note_l)

func _build_foot() -> void:
	var foot := HBoxContainer.new()
	foot.name = "Foot"
	foot.add_theme_constant_override("separation", 10)
	add_child(foot)
	back_b = Button.new()
	back_b.name = "Back"
	back_b.text = "Back"
	back_b.custom_minimum_size = Vector2(124, 60)
	back_b.pressed.connect(back)
	foot.add_child(back_b)
	var steps := HBoxContainer.new()
	steps.name = "Steps"
	steps.size_flags_horizontal = SIZE_EXPAND_FILL
	steps.alignment = BoxContainer.ALIGNMENT_CENTER
	steps.add_theme_constant_override("separation", 5)
	foot.add_child(steps)
	for k in SHORT.size():
		var b := Button.new()
		b.name = "S%d" % (k + 1)
		b.text = "%d %s" % [k + 1, SHORT[k]]
		b.theme_type_variation = &"TabButton"
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 60)
		b.add_theme_font_size_override("font_size", 16)
		b.pressed.connect(go.bind(k))
		steps.add_child(b)
		step_bs.append(b)
	next_b = Button.new()
	next_b.name = "Next"
	next_b.text = "Next"
	next_b.theme_type_variation = &"PrimaryButton"
	next_b.add_theme_font_size_override("font_size", 28)
	next_b.custom_minimum_size = Vector2(170, 60)
	next_b.pressed.connect(next)
	foot.add_child(next_b)

## A card grid that scrolls by drag (DragScroll) inside a frame with edge fades; the column count re-flows to the width.
func _grid_page(p: Control, k: int, card_w: float) -> GridContainer:
	var frame := Control.new()
	frame.name = "Frame"
	frame.size_flags_vertical = SIZE_EXPAND_FILL
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(frame)
	var sc := DragScroll.new()
	sc.name = "Scroll"
	sc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.add_child(sc)
	var g := GridContainer.new()
	g.name = "Grid"
	g.size_flags_horizontal = SIZE_EXPAND_FILL
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.add_theme_constant_override("h_separation", GAP)
	g.add_theme_constant_override("v_separation", GAP)
	sc.add_child(g)
	var fade := EdgeFade.new(sc)
	fade.name = "Fade"
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.add_child(fade)
	sc.tapped.connect(func(c: Control) -> void:
		var j := c.get_node_or_null("Juicy")
		if j: j._release())
	_grids[k] = [sc, g, card_w, fade]
	sc.resized.connect(_reflow.bind(k))
	return g

func _reflow(k: int) -> void:
	var e: Array = _grids[k]
	var sc: DragScroll = e[0]
	var w := sc.size.x - 16.0   # room for the scroll bar
	var g: GridContainer = e[1]
	# never more columns than cards, so a short row (5 characters) spreads over the width
	g.columns = clampi(int((w + GAP) / (float(e[2]) + GAP)), 1, maxi(1, g.get_child_count()))
	if k == P_CHAR:   # character cards: one row fills the page height (bigger renders), more rows keep the base size
		var rows := ceili(g.get_child_count() / float(g.columns))
		var h := CLASS_CARD.y if rows > 1 else clampf(sc.size.y - 2.0, CLASS_CARD.y, 380.0)
		for c: Control in g.get_children(): c.custom_minimum_size.y = h
	(e[3] as Control).queue_redraw()

## A selectable card: optional art on top, a heavy title, a muted line or two.
func _card(title: String, sub: String, size: Vector2, art: Control = null) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.custom_minimum_size = size
	b.size_flags_horizontal = SIZE_EXPAND_FILL
	for k in _styles: b.add_theme_stylebox_override(k, _styles[k])
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for s in ["left", "right"]: m.add_theme_constant_override("margin_" + s, 12)
	m.add_theme_constant_override("margin_top", 10)
	m.add_theme_constant_override("margin_bottom", 12)
	b.add_child(m)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 4)
	m.add_child(v)
	if art:
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.size_flags_vertical = SIZE_EXPAND_FILL
		v.add_child(art)
	var t := _label(title, 22, "", true)
	t.name = "Name"
	t.add_theme_font_override("font", _heavy)
	v.add_child(t)
	if sub != "":
		var s := _label(sub, 15, "MutedLabel")
		s.name = "Sub"
		s.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		s.clip_text = true
		if art == null:   # text-only cards: two lines of description
			s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			s.max_lines_visible = 2
			s.size_flags_vertical = SIZE_EXPAND_FILL
		v.add_child(s)
	return b

## A row of pill toggles (one ButtonGroup) after a muted label.
func _pills(parent: Control, row_name: String, label: String, keys: Array, names: Array, store: Dictionary, on_pick: Callable, min_w := 0.0) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = row_name
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var l := _label(label, 18, "MutedLabel")
	l.custom_minimum_size = Vector2(124, 0)
	l.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(l)
	var g := ButtonGroup.new()
	for i in keys.size():
		var b := Button.new()
		b.name = "P" + str(keys[i])
		b.text = str(names[i])
		b.theme_type_variation = &"TabButton"
		b.toggle_mode = true
		b.button_group = g
		b.custom_minimum_size = Vector2(min_w, 60)
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 20)
		b.pressed.connect(on_pick.bind(keys[i]))
		row.add_child(b)
		store[keys[i]] = b
	return row

func _build_mode(p: Control) -> void:
	var g := _grid_page(p, P_MODE, MODE_CARD.x)
	var grp := ButtonGroup.new()
	for m: String in modes():
		var b := _card(mode_name(m), ModeRules.blurb(m, Content.modes), MODE_CARD)
		b.name = m
		b.button_group = grp
		b.pressed.connect(set_mode.bind(m))
		g.add_child(b)
		scroll_of(P_MODE).add_card(b)
		_mode_bs[m] = b
	var names: Array = []
	for k: String in Dynamics.KINDS: names.append(Dynamics.NAMES[k])
	var row := _pills(p, "Floor", "Moving floor", Dynamics.KINDS, names, _dyn_bs, set_dyn)
	row.tooltip_text = "Does the arena floor move? Random = a different moving floor every match"

func _build_arena(p: Control) -> void:
	_grid_page(p, P_ARENA, MAP_CARD.x)
	_rebuild_maps()

func _rebuild_maps() -> void:
	if not _grids.has(P_ARENA): return
	var g: GridContainer = _grids[P_ARENA][1]
	for c in g.get_children(): c.queue_free(); g.remove_child(c)
	_map_bs.clear()
	var grp := ButtonGroup.new()
	for id: String in maps_for(mode_id):
		var m := Content.get_map(id)
		var tags: Array = m.get("tags", [])
		var b := _card(map_name(id), " · ".join(tags.slice(0, 3)), MAP_CARD, MapThumb.new(m, id))
		b.name = id
		b.button_group = grp
		b.tooltip_text = str(m.get("blurb", ""))
		b.pressed.connect(set_map.bind(id))
		g.add_child(b)
		scroll_of(P_ARENA).add_card(b)
		_map_bs[id] = b
		JuicyButton.attach(b)
	_reflow(P_ARENA)

func _build_players(p: Control) -> void:
	p.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_theme_constant_override("separation", 16)
	players_l = _label("", 40, "TitleLabel")
	players_l.name = "Headline"
	players_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(players_l)
	var ns: Array = []
	for n in range(BOT_MIN, BOT_MAX + 1): ns.append(n)
	_pills(p, "Bots", "Bots", ns, ns, _bot_bs, set_bots, 64)
	var dn: Array = []
	for d: String in DIFFS: dn.append(d.capitalize())
	_pills(p, "Skill", "Bot skill", DIFFS, dn, _diff_bs, set_diff, 100)
	players_hint = _label("", 17, "MutedLabel", true)
	players_hint.name = "Hint"
	players_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(players_hint)

func _build_class(p: Control) -> void:
	var g := _grid_page(p, P_CHAR, CLASS_CARD.x)
	var grp := ButtonGroup.new()
	for id: String in Content.classes:
		var c := Content.get_class_data(id)
		var art := TextureRect.new()
		art.name = "Render"
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.custom_minimum_size = Vector2(0, 120)
		var b := _card(class_name_of(id), str(c.get("tag", "")), CLASS_CARD, art)
		b.name = id
		b.button_group = grp
		b.pressed.connect(set_class.bind(id))
		g.add_child(b)
		scroll_of(P_CHAR).add_card(b)
		_class_bs[id] = b
		_class_art[id] = art

func _build_start(p: Control) -> void:
	p.alignment = BoxContainer.ALIGNMENT_CENTER
	var hint := _label("Check your match. Tap a row to change it.", 18, "MutedLabel", true)
	hint.name = "Hint"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(hint)
	var keys := ["Game type", "Arena", "Players", "Character"]
	for k in keys.size():
		var b := Button.new()
		b.name = keys[k].replace(" ", "")
		b.custom_minimum_size = Vector2(0, 60)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(go.bind(k))
		var h := HBoxContainer.new()
		h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		h.offset_left = 20; h.offset_right = -20
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_theme_constant_override("separation", 16)
		b.add_child(h)
		var kl := _label(keys[k], 18, "MutedLabel")
		kl.custom_minimum_size = Vector2(120, 0)
		kl.size_flags_vertical = SIZE_SHRINK_CENTER
		h.add_child(kl)
		var vl := _label("", 22, "", true)
		vl.name = "Value"
		vl.add_theme_font_override("font", _heavy)
		vl.size_flags_horizontal = SIZE_EXPAND_FILL
		vl.size_flags_vertical = SIZE_SHRINK_CENTER
		h.add_child(vl)
		var ed := _label("Change", 16, "MutedLabel")
		ed.size_flags_vertical = SIZE_SHRINK_CENTER
		h.add_child(ed)
		p.add_child(b)
		_sum_bs.append(b)
		_sum_vals.append(vl)

# ---------------- refresh ----------------

func _refresh() -> void:
	if title_l == null: return
	title_l.text = TITLES[page]
	step_l.text = "Step %d of %d" % [page + 1, TITLES.size()]
	var n := note
	if n == "" and page == P_ARENA:
		n = "Arenas for %s" % mode_name(mode_id)
	note_l.text = n
	note_l.tooltip_text = n
	back_b.text = "Back"
	next_b.text = "Start" if page == pages.size() - 1 else "Next"
	for k in step_bs.size():
		(step_bs[k] as Button).set_pressed_no_signal(k == page)
	_select(_map_bs, map_id)
	_select(_mode_bs, mode_id)
	_select(_dyn_bs, dyn)
	_select(_class_bs, cls)
	_select(_diff_bs, diff)
	var team := is_team_mode()
	var flex := is_flex_teams()
	var total := bot_total()
	for n2 in _bot_bs:
		var b: Button = _bot_bs[n2]
		var fixed := ModeRules.fixed_bots(mode_id, Content.modes) >= 0     # Pillars / Practice Range set the count
		b.disabled = (team and not flex and n2 != total) or (flex and n2 % 2 == 0) or (fixed and n2 != total)
		b.set_pressed_no_signal(n2 == (total if team or fixed else bots))
	if players_l:
		players_l.text = _players_text()
		var t := ModeRules.team_size(mode_id, Content.modes, total)
		if flex: players_hint.text = "Bots are computer players. Two teams: %d vs %d (odd bot counts keep it even)." % [t, t]
		elif team: players_hint.text = "Bots are computer players. %s fixes the teams: %d vs %d." % [mode_name(mode_id), t, t]
		elif mode_id == "practice": players_hint.text = "The range has %d dummies: they stand, slide and pop back up. They never fight back." % total
		elif ModeRules.fixed_bots(mode_id, Content.modes) >= 0: players_hint.text = "%s fills every pillar: you + %d bots, one life each." % [mode_name(mode_id), total]
		else: players_hint.text = "Bots are computer players. Free for all: they fight you and each other."
	if _sum_vals.size() == 4:
		_sum_vals[0].text = "%s · Floor: %s" % [mode_name(mode_id), Dynamics.NAMES.get(dyn, dyn)]
		_sum_vals[1].text = map_name(map_id)
		_sum_vals[2].text = "%s · %s" % [_players_text(), diff.capitalize()]
		_sum_vals[3].text = class_name_of(cls)

func _select(store: Dictionary, key: Variant) -> void:
	for k in store:
		(store[k] as Button).set_pressed_no_signal(k == key)

# ---------------- scroll edge hint ----------------

## Soft dark fades over the top / bottom edge of a card grid while more cards are hidden there (the scroll hint,
## together with the scroll bar and the half-visible next row).
class EdgeFade extends Control:
	const H := 26.0
	var sc: DragScroll

	func _init(s: DragScroll) -> void:
		sc = s
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		s.get_v_scroll_bar().value_changed.connect(func(_v: float) -> void: queue_redraw())
		s.get_v_scroll_bar().changed.connect(queue_redraw)

	func _draw() -> void:
		var m := sc.max_scroll()
		if m <= 1.0: return
		var w := size.x - 16.0
		var c0 := Color(0.04, 0.12, 0.15, 0.0)
		var c1 := Color(0.04, 0.12, 0.15, 0.75)
		if sc.scroll_vertical > 1:
			draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, H), Vector2(0, H)]), PackedColorArray([c1, c1, c0, c0]))
		if sc.scroll_vertical < m - 1:
			var y := size.y
			draw_polygon(PackedVector2Array([Vector2(0, y - H), Vector2(w, y - H), Vector2(w, y), Vector2(0, y)]), PackedColorArray([c0, c0, c1, c1]))

# ---------------- card art ----------------

## Map card art: a picture of the level (res://ui/map_thumbs/<id>.jpg, rendered once from the real map by
## `tools/shoot-godot-maps.sh thumbs`); without one, the map's sky (skyTop -> sky), its hill colours as low-poly hills
## and a floor slab.
class MapThumb extends Control:
	var sky_top: Color
	var sky: Color
	var hills: Array = []
	var floor_c: Color
	var tex: Texture2D

	func _init(m: Dictionary, id := "") -> void:
		sky = _c(m.get("sky", 0x9ad0f0))
		sky_top = _c(m.get("skyTop", null)) if m.get("skyTop") != null else sky.lightened(0.25)
		for h in m.get("hills", []): hills.append(_c(h))
		if hills.is_empty(): hills = [sky.darkened(0.3)]
		floor_c = _c(m.get("voidColor", 0x7a8a90)).lerp(Color(0.85, 0.85, 0.8), 0.35)
		var p := "res://ui/map_thumbs/%s.jpg" % id
		if id != "" and ResourceLoader.exists(p):
			tex = load(p)
		custom_minimum_size = Vector2(0, 60)
		clip_contents = true

	static func _c(v: Variant) -> Color:
		if v is String: return Color(v)
		var i := int(v)
		return Color8((i >> 16) & 255, (i >> 8) & 255, i & 255)

	func _draw() -> void:
		var w := size.x
		var h := size.y
		if tex:
			var ts := tex.get_size()
			var sc := maxf(w / ts.x, h / ts.y)
			var src := Rect2((ts - Vector2(w, h) / sc) / 2.0, Vector2(w, h) / sc)
			draw_texture_rect_region(tex, Rect2(Vector2.ZERO, size), src)
			draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.12), false, 2.0)
			return
		var cols := PackedColorArray([sky_top, sky_top, sky, sky])
		draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)]), cols)
		var n := hills.size()
		for i in n:
			var c: Color = hills[i]
			var x0 := w * (float(i) / n) - w * 0.2
			var x1 := x0 + w * 0.65
			var peak := h * (0.35 + 0.12 * (i % 2))
			draw_colored_polygon(PackedVector2Array([Vector2(x0, h), Vector2((x0 + x1) * 0.5, peak), Vector2(x1, h)]), c)
		draw_colored_polygon(PackedVector2Array([Vector2(w * 0.18, h), Vector2(w * 0.3, h * 0.72), Vector2(w * 0.7, h * 0.72), Vector2(w * 0.82, h)]), floor_c)
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.12), false, 2.0)

