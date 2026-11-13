class_name SetupWizard
extends VBoxContainer
## Offline match setup, one choice per page (title screen Play opens it):
##   1 Game type (cards for ModeRules.PLAYABLE, read from code),
##   2 Arena (cards for the maps that game type allows, and the Moving floor row: Settings "dyn"), 3 Players (you + 1..7 bots, team modes fix the count; bot
##   skill), 4 Character (Content.classes, real 3D renders of the Wobbler: ui/character_stage.gd), 5 Start (a summary
##   of the four picks, each row jumps back to its page, and the big Start button).
## Every pick is saved in Settings straight away (mode, offline_map, dyn, bots, difficulty, class), so the next Play
## starts where the last one ended. Game types restrict arenas: when the remembered arena is not allowed in the new
## game type, the wizard moves to the nearest allowed one and says so in one line (`note`).
## Game types are grouped in labelled sections (Classic / Team / Special, data/extra/wizard.json: also each card's short
## line, colour and drawn icon; the selected card's full text shows in a detail line under the grid). The Moving floor
## row lives on the Arena page. Character cards show the class parameters as bars (logic/class_stats.gd).
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
const MAP_CARD := Vector2(220, 148)
const MODE_CARD := Vector2(220, 136)
const CLASS_CARD := Vector2(172, 282)
const PAD := 8                  ## room round a card grid inside its scroll area, so a card's ring / shadow is never clipped
const TEXT_PATH := "res://data/extra/wizard.json"

var page := 0
var class_only := false     ## set before add_child: only the Character page (no header, footer or other pages); the Arcade hub embeds it (dlc/construction/construction_hub.gd)
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
var dots: StepDots                ## the five progress dots in the footer
var players_l: Label
var players_hint: Label
var stage: CharacterStage   ## the shared 3D stage for the character cards
var _grids := {}            ## page index -> [DragScroll, first GridContainer, card width, EdgeFade, [every GridContainer]]
var detail_l: Label         ## the selected game type's full text (under the grid)
var _checks := {}           ## card Button -> its selected tick
static var _text: Dictionary = {}
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

## Game types the wizard offers: every mode the port plays offline (ModeRules.PLAYABLE). Construction is not here: it
## lives behind the title's Construction banner (dlc/construction/construction_hub.gd).
static func modes() -> Array:
	var out: Array = []
	for m: String in ModeRules.PLAYABLE:
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

## Godot-only display text (data/extra/wizard.json): sections, short card lines, colours, icons.
static func text_data() -> Dictionary:
	if _text.is_empty():
		var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(TEXT_PATH)) if FileAccess.file_exists(TEXT_PATH) else null
		_text = v if v is Dictionary else {"sections": [], "modes": {}}
	return _text

static func mode_info(m: String) -> Dictionary:
	var d: Variant = text_data().get("modes", {}).get(m)
	return d if d is Dictionary else {}

## The short card line of a game type (never truncated: tests measure it).
static func mode_short(m: String) -> String:
	return str(mode_info(m).get("short", ModeRules.blurb(m, Content.modes)))

## The full text of a game type (the detail line).
static func mode_long(m: String) -> String:
	return str(mode_info(m).get("long", Content.modes.get(m, {}).get("desc", mode_short(m))))

static func mode_color(m: String) -> Color:
	return Color(str(mode_info(m).get("col", "#ffcf5a")))

## [[section name, [mode ids]], ...] over `modes()`; a mode the data does not place goes to the last section.
static func sections() -> Array:
	var out: Array = []
	var seen: Array = []
	var all := modes()
	for s: Dictionary in text_data().get("sections", []):
		var ids: Array = []
		for m: String in s.get("modes", []):
			if all.has(m) and not seen.has(m): ids.append(m); seen.append(m)
		if not ids.is_empty(): out.append([str(s.get("name", "")), ids])
	var rest: Array = all.filter(func(m: String) -> bool: return not seen.has(m))
	if not rest.is_empty():
		if out.is_empty(): out.append(["Game types", rest])
		else: (out[-1][1] as Array).append_array(rest)
	return out

## Classes you own (Save autoload; the Godot-only ones need coins or an unlock, ExtraClasses). Headless helpers without
## the autoload treat every class as owned.
static func owns_class(id: String) -> bool:
	var sv: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Save")
	return sv == null or sv.owns_class(id)

static func class_name_of(id: String) -> String:
	return str(Content.get_class_data(id).get("name", id))

## The last setup in one line (title screen Play tooltip).
func summary_line() -> String:
	return tr("%s · %s · %s") % [tr(mode_name(mode_id)), tr(map_name(map_id)), _players_text()]

func _players_text() -> String:
	var t := bot_total()
	if mode_id == "practice": return tr("You + %d dummies") % t
	return (tr("You + %d bot") if t == 1 else tr("You + %d bots")) % t

## Loads the remembered choices from Settings (and fixes anything no longer valid).
func load_settings() -> void:
	var ms := modes()
	mode_id = str(Settings.get_value("mode", "classic"))
	var stale := not ms.has(mode_id)      # (the hub's Construction start leaves mode = construction and its site map in Settings)
	if stale: mode_id = "classic" if ms.has("classic") else ms[0]
	dyn = str(Settings.get_value("dyn", "random"))
	if not Dynamics.KINDS.has(dyn): dyn = "random"
	bots = clampi(int(Settings.get_value("bots", 3)), BOT_MIN, BOT_MAX)
	diff = str(Settings.get_value("difficulty", "normal"))
	if not DIFFS.has(diff): diff = "normal"
	cls = str(Settings.get_value("class", "wobbler"))
	if not Content.classes.has(cls) or not owns_class(cls): cls = "wobbler"
	_want_map = "arena" if stale else str(Settings.get_value("offline_map", "arena"))
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
		note = tr("%s has no %s: arena is now %s.") % [tr(mode_name(m)), tr(map_name(map_id)), tr(map_name(to))]
	elif to != map_id:
		note = tr("Arena back to %s.") % tr(map_name(to))
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
	page = P_CHAR if class_only else clampi(i, 0, pages.size() - 1)
	_sync_classes()
	for k in pages.size():
		(pages[k] as Control).visible = k == page
	_refresh()
	if stage:
		stage.active = page == P_CHAR and is_visible_in_tree()
		if page == P_CHAR: _bake()
	_reveal_selected.call_deferred()
	if Tier.is_pc(): next_b.grab_focus.call_deferred()

## Only the classes you own get a card (the Shop sells, playing unlocks the rest); follows a class picked in the Walldrobe.
func _sync_classes() -> void:
	var want := str(Settings.get_value("class", cls))
	if want != cls and Content.classes.has(want) and owns_class(want): cls = want
	for id: String in _class_bs: (_class_bs[id] as Control).visible = owns_class(id)
	if _grids.has(P_CHAR): _reflow(P_CHAR)

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
	add_theme_constant_override("separation", UiTheme.SP_3)
	size_flags_vertical = SIZE_EXPAND_FILL

func _ready() -> void:
	if _heavy == null: _heavy = UiTheme.font(700)
	_make_styles()
	if not _loaded: load_settings()
	stage = CharacterStage.new()
	stage.size = Vector2i(300, 300)     # the card art is about as wide as it is tall
	stage.min_radius = 0.95             # the whole pedestal stays in the card
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
		p.add_theme_constant_override("separation", UiTheme.SP_3)
		body.add_child(p)
		pages.append(p)
	_build_mode(pages[P_MODE])
	_build_arena(pages[P_ARENA])
	_build_players(pages[P_PLAYERS])
	_build_class(pages[P_CHAR])
	_build_start(pages[P_START])
	_build_foot()
	JuicyButton.attach_all(self)
	if class_only:
		for n in ["Head", "Foot"]: get_node(n).visible = false
		set_process_unhandled_input(false)
	go(page)

func _bake() -> void:
	var ids: Array = Content.classes.keys().filter(owns_class)
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
	foot.add_theme_constant_override("separation", UiTheme.SP_3)
	add_child(foot)
	back_b = Button.new()
	back_b.name = "Back"
	back_b.text = "Back"
	back_b.custom_minimum_size = Vector2(124, 60)
	back_b.pressed.connect(back)
	foot.add_child(back_b)
	dots = StepDots.new()               # progress only (Back / Next move; a summary row on the last page jumps back): 3 buttons in the bar
	dots.name = "Steps"
	dots.n = SHORT.size()
	dots.size_flags_horizontal = SIZE_EXPAND_FILL
	foot.add_child(dots)
	next_b = Button.new()
	next_b.name = "Next"
	next_b.text = "Next"
	next_b.theme_type_variation = &"PrimaryButton"
	next_b.add_theme_font_size_override("font_size", 28)
	next_b.custom_minimum_size = Vector2(170, 60)
	next_b.pressed.connect(next)
	foot.add_child(next_b)

## A card page that scrolls by drag (DragScroll) inside a frame with edge fades. The scroll holds a padded column
## (`Body`) of one or more card grids (`new_grid`); the column count re-flows to the width. Returns the first grid.
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
	var pad := MarginContainer.new()
	pad.name = "Pad"
	pad.size_flags_horizontal = SIZE_EXPAND_FILL
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_top", PAD)
	pad.add_theme_constant_override("margin_bottom", PAD)
	pad.add_theme_constant_override("margin_left", 4)
	pad.add_theme_constant_override("margin_right", 4)
	sc.add_child(pad)
	var body := VBoxContainer.new()
	body.name = "Body"
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_theme_constant_override("separation", UiTheme.SP_3)
	pad.add_child(body)
	var fade := EdgeFade.new(sc)
	fade.name = "Fade"
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.add_child(fade)
	sc.tapped.connect(func(c: Control) -> void:
		var j := c.get_node_or_null("Juicy")
		if j: j._release())
	_grids[k] = [sc, null, card_w, fade, []]
	sc.resized.connect(_reflow.bind(k))
	var g := new_grid(k)
	_grids[k][1] = g
	return g

## Another card grid in page `k`'s column (a game type section), after an optional section header.
func new_grid(k: int, header := "", col := Color(1, 0.812, 0.353)) -> GridContainer:
	var body: VBoxContainer = (_grids[k][0] as Control).get_node("Pad/Body")
	if header != "":
		body.add_child(_section_head(header, col))
	var g := GridContainer.new()
	g.name = "Grid"
	g.size_flags_horizontal = SIZE_EXPAND_FILL
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.add_theme_constant_override("h_separation", GAP)
	g.add_theme_constant_override("v_separation", GAP)
	body.add_child(g)
	(_grids[k][4] as Array).append(g)
	return g

## "CLASSIC ────────": a small heavy caption in the section colour, then a hairline.
func _section_head(text: String, col: Color) -> Control:
	var h := HBoxContainer.new()
	h.name = "Head_" + text
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", UiTheme.SP_3)
	var dot := ColorRect.new()
	dot.color = col
	dot.custom_minimum_size = Vector2(6, 20)
	dot.size_flags_vertical = SIZE_SHRINK_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(dot)
	var l := _label(tr(text).to_upper(), 18)
	l.name = "Caption"
	l.add_theme_font_override("font", _heavy)
	l.add_theme_color_override("font_color", col)
	h.add_child(l)
	var line := ColorRect.new()
	line.color = Color(1, 1, 1, 0.14)
	line.custom_minimum_size = Vector2(0, 2)
	line.size_flags_horizontal = SIZE_EXPAND_FILL
	line.size_flags_vertical = SIZE_SHRINK_CENTER
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(line)
	return h

func _reflow(k: int) -> void:
	var e: Array = _grids[k]
	var sc: DragScroll = e[0]
	var w := sc.size.x - 16.0 - 8.0   # room for the scroll bar and the side padding
	var grids: Array = e[4]
	var most := 1
	for g: GridContainer in grids: most = maxi(most, g.get_child_count())
	# never more columns than cards, so a short row (5 characters) spreads over the width
	var cols := clampi(int((w + GAP) / (float(e[2]) + GAP)), 1, most)
	for g: GridContainer in grids: g.columns = cols
	if k == P_CHAR:   # character cards: one row fills the page height (bigger renders), more rows keep the base size
		var g: GridContainer = grids[0]
		var shown := g.get_children().filter(func(c: Control) -> bool: return c.visible).size()   # (classes you do not own are hidden)
		var rows := ceili(maxi(1, shown) / float(g.columns))
		var h := CLASS_CARD.y if rows > 1 else clampf(sc.size.y - 2.0 * PAD - 2.0, CLASS_CARD.y, 400.0)
		for c: Control in g.get_children(): c.custom_minimum_size.y = h
	(e[3] as Control).queue_redraw()

## A selectable card: optional art on top (or a small icon beside the title), a heavy title, a muted line or two, and a
## tick in the corner while it is the pick.
func _card(title: String, sub: String, size: Vector2, art: Control = null, icon: Control = null) -> Button:
	if art == null: sub = sub.replace("\n", " · ")     # one flowing description (a hard line break made a 4th line in French)
	var b := Button.new()
	b.toggle_mode = true
	b.custom_minimum_size = size
	b.size_flags_horizontal = SIZE_EXPAND_FILL
	for k in _styles: b.add_theme_stylebox_override(k, _styles[k])
	var m := MarginContainer.new()
	m.name = "Margin"
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for s in ["left", "right"]: m.add_theme_constant_override("margin_" + s, 12)
	m.add_theme_constant_override("margin_top", 10)
	m.add_theme_constant_override("margin_bottom", 12)
	b.add_child(m)
	var v := VBoxContainer.new()
	v.name = "Col"
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
	t.size_flags_horizontal = SIZE_EXPAND_FILL
	if icon:
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var row := HBoxContainer.new()
		row.name = "Title"
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 8)
		v.add_child(row)
		row.add_child(icon)
		t.size_flags_vertical = SIZE_SHRINK_CENTER
		row.add_child(t)
		t.add_theme_constant_override("line_spacing", 0)
		t.custom_minimum_size.x = 40
		t.add_theme_font_size_override("font_size", 21)
	else:
		v.add_child(t)
	if sub != "":
		var s := _label(sub, 15, "MutedLabel")
		s.name = "Sub"
		s.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		s.clip_text = true
		if art == null:   # text-only cards: two lines of description
			s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			s.max_lines_visible = 3
			s.size_flags_vertical = SIZE_EXPAND_FILL
		v.add_child(s)
	t.resized.connect(_fit_title.bind(t, 21 if icon else 22))
	var tick := Tick.new()
	tick.name = "Check"
	tick.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	tick.offset_left = -Tick.SIZE - 6; tick.offset_right = -6; tick.offset_top = 6; tick.offset_bottom = Tick.SIZE + 6
	tick.visible = false
	b.add_child(tick)
	_checks[b] = tick
	return b

## A card title never trims: the font shrinks (down to 15) until the name fits the width it got.
func _fit_title(l: Label, base: int) -> void:
	if l.size.x < 8.0: return
	var f := l.get_theme_font("font")
	var fs := base
	while fs > 15 and f.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > l.size.x:
		fs -= 1
	if f.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > l.size.x and l.text.contains(" "):
		fs = 17                     # still too long (French): two lines at a slightly smaller size, never an ellipsis
		if l.autowrap_mode == TextServer.AUTOWRAP_OFF:
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.max_lines_visible = 2
			l.clip_text = false
	if l.get_theme_font_size("font_size") != fs: l.add_theme_font_size_override("font_size", fs)

## A row of pill toggles (one ButtonGroup) after a muted label.
func _pills(parent: Control, row_name: String, label: String, keys: Array, names: Array, store: Dictionary, on_pick: Callable, min_w := 0.0) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = row_name
	row.add_theme_constant_override("separation", UiTheme.SP_3)
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
	_grid_page(p, P_MODE, MODE_CARD.x)
	var secs := sections()
	var grp := ButtonGroup.new()
	var first := true
	for sec: Array in secs:
		var ids: Array = sec[1]
		var g: GridContainer = _grids[P_MODE][1] if first else null
		var sc_col := mode_color(ids[0])
		if first:   # the grid made with the page gets the first section's header in front of it
			var body: VBoxContainer = scroll_of(P_MODE).get_node("Pad/Body")
			body.add_child(_section_head(sec[0], sc_col))
			body.move_child(body.get_child(body.get_child_count() - 1), 0)
		else:
			g = new_grid(P_MODE, sec[0], sc_col)
		first = false
		for m: String in ids:
			var b := _card(mode_name(m), mode_short(m), MODE_CARD, null, ModeIcon.new(str(mode_info(m).get("icon", "crate")), mode_color(m)))
			b.name = m
			b.button_group = grp
			b.tooltip_text = mode_long(m)
			b.pressed.connect(set_mode.bind(m))
			g.add_child(b)
			scroll_of(P_MODE).add_card(b)
			_mode_bs[m] = b
	detail_l = _label("", 17, "MutedLabel")
	detail_l.name = "Detail"
	detail_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_l.max_lines_visible = 2
	detail_l.custom_minimum_size.y = 46
	detail_l.size_flags_vertical = SIZE_SHRINK_END
	p.add_child(detail_l)

func _build_arena(p: Control) -> void:
	var names: Array = []
	for k: String in Dynamics.KINDS: names.append(Dynamics.NAMES[k])
	var row := _pills(p, "Floor", "Moving floor", Dynamics.KINDS, names, _dyn_bs, set_dyn)
	row.tooltip_text = "Does the arena floor move? Random = a different moving floor every match"
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
		var b := _card(map_name(id), " · ".join(tags.slice(0, 2).map(func(t: Variant) -> String: return tr(str(t)))), MAP_CARD, MapThumb.new(m, id))
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
	for d: String in DIFFS: dn.append(tr(d.capitalize()))
	_pills(p, "Skill", "Bot skill", DIFFS, dn, _diff_bs, set_diff, 100)
	players_hint = _label("", 17, "MutedLabel", true)
	players_hint.name = "Hint"
	players_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(players_hint)

func _build_class(p: Control) -> void:
	var g := _grid_page(p, P_CHAR, CLASS_CARD.x)
	var grp := ButtonGroup.new()
	for id: String in Content.classes:
		var art := TextureRect.new()
		art.name = "Render"
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.custom_minimum_size = Vector2(0, 84)
		var b := _card(class_name_of(id), "", CLASS_CARD, art)
		b.name = id
		b.button_group = grp
		b.tooltip_text = "%s\n%s" % [str(Content.get_class_data(id).get("tag", "")), ClassStats.describe(Content.get_class_data(id))]
		b.pressed.connect(set_class.bind(id))
		b.get_node("Margin/Col").add_child(_stat_grid(id))
		g.add_child(b)
		scroll_of(P_CHAR).add_card(b)
		_class_bs[id] = b
		_class_art[id] = art

## The class parameters as bars: two columns of (tiny label over a bar), one cell per ClassStats entry.
func _stat_grid(id: String) -> GridContainer:
	var g := GridContainer.new()
	g.name = "Stats"
	g.columns = 2
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.add_theme_constant_override("h_separation", 10)
	g.add_theme_constant_override("v_separation", 3)
	for st: Array in ClassStats.bars(Content.get_class_data(id)):
		var cell := VBoxContainer.new()
		cell.name = str(st[0])
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.size_flags_horizontal = SIZE_EXPAND_FILL
		cell.add_theme_constant_override("separation", 1)
		var l := _label(str(st[0]), 15, "MutedLabel")
		l.name = "Label"
		l.clip_text = false
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART      # a long name ("Résistance au recul") wraps instead of running into its neighbour
		l.custom_minimum_size.x = 40
		cell.add_child(l)
		var bar := StatBar.new(float(st[1]), float(st[2]))
		bar.name = "Bar"
		cell.add_child(bar)
		g.add_child(cell)
	return g

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
	step_l.text = tr("Step %d of %d") % [page + 1, TITLES.size()]
	var n := note
	if n == "" and page == P_ARENA:
		n = tr("Arenas for %s") % tr(mode_name(mode_id))
	note_l.text = n
	note_l.tooltip_text = n
	back_b.text = "Back"
	next_b.text = "Start" if page == pages.size() - 1 else "Next"
	dots.page = page
	dots.tooltip_text = tr(SHORT[page])
	_select(_map_bs, map_id)
	_select(_mode_bs, mode_id)
	if detail_l: detail_l.text = tr("%s: %s") % [tr(mode_name(mode_id)), tr(mode_long(mode_id))]
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
		if flex: players_hint.text = tr("Bots are computer players. Two teams: %d vs %d (odd bot counts keep it even).") % [t, t]
		elif team: players_hint.text = tr("Bots are computer players. %s fixes the teams: %d vs %d.") % [tr(mode_name(mode_id)), t, t]
		elif mode_id == "practice": players_hint.text = tr("The range has %d dummies: they stand, slide and pop back up. They never fight back.") % total
		elif ModeRules.fixed_bots(mode_id, Content.modes) >= 0: players_hint.text = tr("%s fills every pillar: you + %d bots, one life each.") % [tr(mode_name(mode_id)), total]
		else: players_hint.text = "Bots are computer players. Free for all: they fight you and each other."
	if _sum_vals.size() == 4:
		_sum_vals[0].text = mode_name(mode_id)
		_sum_vals[1].text = tr("%s · Floor: %s") % [tr(map_name(map_id)), tr(Dynamics.NAMES.get(dyn, dyn))]
		_sum_vals[2].text = tr("%s · %s") % [_players_text(), tr(diff.capitalize())]
		_sum_vals[3].text = class_name_of(cls)

func _select(store: Dictionary, key: Variant) -> void:
	for k in store:
		var b := store[k] as Button
		b.set_pressed_no_signal(k == key)
		var t: Control = _checks.get(b)
		if t and is_instance_valid(t): t.visible = k == key

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



## A class parameter bar: a dark track, the value in the accent colour and a small tick where the Wobbler sits.
class StatBar extends Control:
	var v: float
	var base: float

	func _init(value: float, baseline: float) -> void:
		v = value
		base = baseline
		custom_minimum_size = Vector2(0, 10)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var track := StyleBoxFlat.new()
		track.bg_color = Color(0, 0, 0, 0.38)
		track.set_corner_radius_all(4)
		draw_style_box(track, r)
		var fill := StyleBoxFlat.new()
		fill.bg_color = UiTheme.ACCENT if v >= base - 0.02 else UiTheme.WARN.darkened(0.15)
		fill.set_corner_radius_all(4)
		draw_style_box(fill, Rect2(0, 0, maxf(8.0, size.x * v), size.y))
		draw_rect(Rect2(size.x * base - 1.0, -1.0, 2.0, size.y + 2.0), Color(1, 1, 1, 0.85))

## The corner tick of the picked card.
## Five dots, the current page's one a longer gold pill: where you are in the wizard, nothing to tap.
class StepDots extends Control:
	var n := 5
	var page := 0:
		set(v):
			page = v
			queue_redraw()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(120, 20)

	func _draw() -> void:
		var w := 12.0
		var gap := 12.0
		var cur := 40.0
		var total := (n - 1) * (w + gap) + cur
		var x := (size.x - total) / 2.0
		var y := size.y / 2.0
		for k in n:
			var cw := cur if k == page else w
			var r := Rect2(x, y - w / 2.0, cw, w)
			var col := UiTheme.ACCENT if k == page else (Color(1, 1, 1, 0.55) if k < page else Color(1, 1, 1, 0.2))
			draw_style_box(UiTheme.box(col, 6, Color(0, 0, 0, 0), 0, 0), r)
			x += cw + gap

class Tick extends Control:
	const SIZE := 24.0

	func _init() -> void:
		custom_minimum_size = Vector2(SIZE, SIZE)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_circle(size * 0.5, size.x * 0.5, UiTheme.ACCENT)
		var u := size.x
		draw_polyline(PackedVector2Array([Vector2(0.27, 0.52) * u, Vector2(0.44, 0.69) * u, Vector2(0.75, 0.32) * u]), UiTheme.INK, 3.0, true)

## A game type's small vector icon on a tinted badge: no assets, drawn from rects, circles and polygons.
class ModeIcon extends Control:
	var kind: String
	var col: Color
	const INK := Color(0.0627, 0.1686, 0.2078)

	func _init(k: String, c: Color) -> void:
		kind = k
		col = c
		custom_minimum_size = Vector2(36, 36)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _p(x: float, y: float) -> Vector2:
		return Vector2(x, y) * size.x

	func _poly(pts: Array, c: Color) -> void:
		var a := PackedVector2Array()
		for q: Vector2 in pts: a.append(_p(q.x, q.y))
		draw_colored_polygon(a, c)

	func _rect(x: float, y: float, w: float, h: float, c: Color) -> void:
		draw_rect(Rect2(_p(x, y), _p(w, h)), c)

	func _star(n: int, r0: float, r1: float, c: Color, at := Vector2(0.5, 0.5)) -> void:
		var pts: Array = []
		for i in n * 2:
			var a := PI * i / n - PI / 2.0
			var r := r0 if i % 2 == 0 else r1
			pts.append(at + Vector2(cos(a), sin(a)) * r)
		_poly(pts, c)

	func _person(x: float, y: float, s: float, c: Color) -> void:
		draw_circle(_p(x, y - 0.17 * s), size.x * 0.09 * s, c)
		_poly([Vector2(x - 0.13 * s, y + 0.22 * s), Vector2(x - 0.1 * s, y - 0.05 * s), Vector2(x + 0.1 * s, y - 0.05 * s), Vector2(x + 0.13 * s, y + 0.22 * s)], c)

	func _draw() -> void:
		var bg := StyleBoxFlat.new()
		bg.bg_color = col.darkened(0.6)
		bg.bg_color.a = 0.9
		bg.border_color = col
		bg.set_border_width_all(2)
		bg.set_corner_radius_all(int(size.x * 0.28))
		draw_style_box(bg, Rect2(Vector2.ZERO, size))
		var g := col.lightened(0.25)
		var u := size.x
		match kind:
			"crate":
				_rect(0.22, 0.3, 0.56, 0.5, g)
				_rect(0.17, 0.24, 0.66, 0.12, col)
				_rect(0.22, 0.52, 0.56, 0.07, INK)
				_rect(0.46, 0.3, 0.08, 0.5, INK)
			"bat":
				draw_line(_p(0.3, 0.72), _p(0.68, 0.32), g, u * 0.12)
				draw_circle(_p(0.7, 0.3), u * 0.11, g)
			"gun":
				_rect(0.2, 0.36, 0.58, 0.15, g)
				_rect(0.74, 0.39, 0.1, 0.09, g)
				_poly([Vector2(0.3, 0.5), Vector2(0.46, 0.5), Vector2(0.4, 0.74), Vector2(0.27, 0.74)], g)
			"star":
				_star(4, 0.32, 0.1, g)
				draw_circle(_p(0.5, 0.5), u * 0.06, INK)
			"bomb":
				draw_circle(_p(0.46, 0.58), u * 0.22, g)
				draw_line(_p(0.6, 0.4), _p(0.72, 0.27), g, u * 0.05)
				draw_circle(_p(0.74, 0.25), u * 0.06, UiTheme.ORANGE)
			"ladder":
				draw_line(_p(0.34, 0.2), _p(0.34, 0.8), g, u * 0.06)
				draw_line(_p(0.66, 0.2), _p(0.66, 0.8), g, u * 0.06)
				for y in [0.3, 0.45, 0.6, 0.74]: draw_line(_p(0.34, y), _p(0.66, y), g, u * 0.05)
			"swords":
				draw_line(_p(0.26, 0.26), _p(0.74, 0.74), g, u * 0.09)
				draw_line(_p(0.74, 0.26), _p(0.26, 0.74), g, u * 0.09)
			"bolt":
				_poly([Vector2(0.56, 0.16), Vector2(0.3, 0.54), Vector2(0.47, 0.54), Vector2(0.4, 0.84), Vector2(0.7, 0.44), Vector2(0.53, 0.44), Vector2(0.64, 0.16)], g)
			"p1v1":
				_person(0.3, 0.55, 1.1, Color("#8fd1ff"))
				_person(0.7, 0.55, 1.1, Color("#ff8f6f"))
			"p2":
				for x in [0.32, 0.68]: _person(x, 0.55, 1.1, g)
			"p3":
				for x in [0.22, 0.5, 0.78]: _person(x, 0.56, 0.9, g)
			"p4":
				for x in [0.16, 0.39, 0.61, 0.84]: _person(x, 0.58, 0.72, g)
			"tdm":
				for x in [0.17, 0.36]: _person(x, 0.56, 0.8, Color("#8fd1ff"))
				for x in [0.64, 0.83]: _person(x, 0.56, 0.8, Color("#ff8f6f"))
			"burst":
				_star(8, 0.36, 0.18, g)
			"giant":
				draw_circle(_p(0.4, 0.54), u * 0.26, g)
				draw_circle(_p(0.76, 0.68), u * 0.1, g)
			"moon":
				draw_circle(_p(0.5, 0.5), u * 0.3, g)
				draw_circle(_p(0.62, 0.4), u * 0.26, col.darkened(0.6))
				draw_circle(_p(0.76, 0.72), u * 0.04, g)
			"pillars":
				_rect(0.2, 0.5, 0.17, 0.3, g)
				_rect(0.42, 0.28, 0.17, 0.52, g)
				_rect(0.64, 0.4, 0.17, 0.4, g)
			"hat":
				var pts: Array = []
				for i in 13:
					var a := PI + PI * i / 12.0
					pts.append(Vector2(0.5, 0.62) + Vector2(cos(a), sin(a)) * 0.3)
				_poly(pts, g)
				_rect(0.15, 0.62, 0.7, 0.1, g)
				_rect(0.46, 0.3, 0.08, 0.3, INK)
			"target":
				draw_circle(_p(0.5, 0.5), u * 0.32, g)
				draw_circle(_p(0.5, 0.5), u * 0.22, INK)
				draw_circle(_p(0.5, 0.5), u * 0.13, g)
				draw_circle(_p(0.5, 0.5), u * 0.05, INK)
			"blocks":
				_rect(0.2, 0.52, 0.29, 0.29, g)
				_rect(0.51, 0.52, 0.29, 0.29, g)
				_rect(0.36, 0.22, 0.29, 0.29, col)
			_:
				draw_circle(_p(0.5, 0.5), u * 0.25, g)
