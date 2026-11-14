class_name RankingSheet
extends Control
## The leaderboard sheet: a themed card with board tabs (K.O.s / Wins / Arcade co-op), the top entries (rank, name,
## score, when it was set), loading / empty / error states, the signed-in player's row highlighted, and a header that
## names the server (ui/server_badge.gd + ServerInfo) plus the Kids-mode note (no scores are sent in Kids mode).
##
## It is opened from the Account sheet's Leaderboard button (ui/account_sheet.gd). Data: AccountApi.fetch_rank /
## submit_rank (docs/PROTOCOL.md 4.1). This file owns no network calls itself: `api` is injected (Save.cloud by default),
## which also lets the headless test feed mock entries with show_entries().

signal closed

const BOARDS := [["kos", "K.O.s"], ["wins", "Wins"], ["arcade", "Arcade"]]
const ROW_H := 46.0
const LIST_H := 300.0
const CARD_W := 580.0
const LIMIT := 20
const KIDS_NOTE := "Kids mode is on: scores are not sent to the leaderboard."

var api: AccountApi
var board := "kos"
var state := "idle"                 ## idle | loading | rows | empty | error
var entries: Array = []
var you := {}                       ## the server's `you` row for the last fetch ({} = guest)
var kids := false
var card: PanelContainer
var badge: ServerBadge
var title_l: Label
var host_l: Label
var note_l: Label
var status_l: Label
var rows: VBoxContainer
var scroll: ScrollContainer
var tabs := {}                      ## board id -> Button
var _built := false

func _init() -> void:
	name = "Ranking"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false

func _ready() -> void:
	ensure_built()
	if api == null and is_inside_tree():
		var sv := get_tree().root.get_node_or_null("Save")
		if sv: api = sv.cloud

## Build the card once (safe to call from open()/show_entries() before the tree is ready, e.g. the test).
func ensure_built() -> void:
	if _built: return
	_built = true
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.02, 0.06, 0.08, 0.88)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if (e is InputEventMouseButton or e is InputEventScreenTouch) and e.pressed: close())
	add_child(dim)
	var cc := CenterContainer.new()
	cc.name = "Center"
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cc)
	card = PanelContainer.new()
	card.name = "Card"
	card.custom_minimum_size = Vector2(CARD_W, 0)
	cc.add_child(card)
	var box := VBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override("separation", UiTheme.SP_3)
	card.add_child(box)

	var head := HBoxContainer.new()
	head.name = "Head"
	head.add_theme_constant_override("separation", UiTheme.SP_3)
	box.add_child(head)
	title_l = Label.new()
	title_l.name = "Title"
	title_l.text = "Leaderboard"
	title_l.theme_type_variation = &"TitleLabel"
	title_l.add_theme_font_size_override("font_size", 30)
	title_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title_l)
	badge = ServerBadge.new()
	badge.name = "ServerBadge"
	head.add_child(badge)
	var close_b := Button.new()
	close_b.name = "Close"
	close_b.text = "Close"
	close_b.add_theme_font_size_override("font_size", 19)
	close_b.pressed.connect(close)
	head.add_child(close_b)

	host_l = Label.new()
	host_l.name = "ServerLine"
	host_l.theme_type_variation = &"MutedLabel"
	host_l.add_theme_font_size_override("font_size", 15)
	box.add_child(host_l)

	var bar := HBoxContainer.new()
	bar.name = "Boards"
	bar.add_theme_constant_override("separation", UiTheme.SP_2)
	box.add_child(bar)
	for pair: Array in BOARDS:
		var b := Button.new()
		b.name = str(pair[0]).capitalize()
		b.text = str(pair[1])
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(0, 44)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 19)
		b.pressed.connect(_pick.bind(str(pair[0])))
		bar.add_child(b)
		tabs[str(pair[0])] = b

	note_l = Label.new()
	note_l.name = "KidsNote"
	note_l.theme_type_variation = &"MutedLabel"
	note_l.add_theme_font_size_override("font_size", 16)
	note_l.add_theme_color_override("font_color", UiTheme.WARN)
	note_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note_l.text = KIDS_NOTE
	note_l.visible = false
	box.add_child(note_l)

	status_l = Label.new()
	status_l.name = "Status"
	status_l.theme_type_variation = &"MutedLabel"
	status_l.add_theme_font_size_override("font_size", 18)
	status_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_l.custom_minimum_size = Vector2(0, 24)
	box.add_child(status_l)

	var head_row := HBoxContainer.new()
	head_row.name = "ColumnHeads"
	head_row.add_theme_constant_override("separation", UiTheme.SP_2)
	box.add_child(head_row)
	for pair: Array in [["#", 54, false], ["Player", 0, true], ["Score", 90, false], ["Set", 110, false]]:
		var l := Label.new()
		l.text = str(pair[0])
		l.theme_type_variation = &"MutedLabel"
		l.add_theme_font_size_override("font_size", 15)
		if int(pair[1]) > 0: l.custom_minimum_size = Vector2(int(pair[1]), 0)
		if bool(pair[2]): l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if str(pair[0]) in ["Score", "Set"] else HORIZONTAL_ALIGNMENT_LEFT
		head_row.add_child(l)

	scroll = ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.custom_minimum_size = Vector2(0, LIST_H)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	rows = VBoxContainer.new()
	rows.name = "Rows"
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 2)
	scroll.add_child(rows)

	var foot := Label.new()
	foot.name = "Foot"
	foot.theme_type_variation = &"MutedLabel"
	foot.add_theme_font_size_override("font_size", 14)
	foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	foot.text = tr("Scores you set while signed in. Arcade ranks the furthest stage, weighted by difficulty.")
	box.add_child(foot)

# ============================== opening ==============================

## Show the sheet. `fetch_now = false` lets a caller (or the test) fill it with show_entries() instead of asking the server.
func open(p_board := "kos", fetch_now := true) -> void:
	ensure_built()
	if api == null and is_inside_tree():
		var sv := get_tree().root.get_node_or_null("Save")
		if sv: api = sv.cloud
	board = p_board if p_board in ["kos", "wins", "arcade"] else "kos"
	kids = AccountApi.kids_mode()
	note_l.visible = kids
	title_l.text = tr("Leaderboard")
	if badge != null:
		badge.setup("")
		var inf := ServerInfo.classify("")
		host_l.text = tr("Scores from %s · %s") % [tr(str(inf["label"])), str(inf["host"])]
	visible = true
	_sync_tabs()
	if fetch_now: refresh()
	else: show_loading()

func close() -> void:
	visible = false
	state = "idle"
	closed.emit()

func _unhandled_input(e: InputEvent) -> void:
	if visible and e.is_action_pressed("ui_cancel") and not e.is_echo():
		close()
		get_viewport().set_input_as_handled()

func _pick(b: String) -> void:
	if b == board:
		_sync_tabs(); return
	board = b
	_sync_tabs()
	refresh()

func _sync_tabs() -> void:
	for k: String in tabs:
		(tabs[k] as Button).set_pressed_no_signal(k == board)

# ============================== data ==============================

## Ask the server for the current board (AccountApi.fetch_rank) and show its rows.
func refresh() -> void:
	if api == null:
		show_error(tr("Can't reach the leaderboard right now. Try again in a moment."))
		return
	show_loading()
	kids = AccountApi.kids_mode()
	note_l.visible = kids
	api.fetch_rank(board, func(r: Dictionary) -> void:
		if not visible: return
		if not bool(r.get("ok", false)):
			show_error(str(r.get("msg", tr("Couldn't load the leaderboard. Check your internet and try again."))))
			return
		you = r.get("you") if r.get("you") is Dictionary else {}
		var list: Array = r.get("entries") if r.get("entries") is Array else []
		if list.is_empty(): show_empty()
		else: show_entries(list, {"you": you}))

func show_loading() -> void:
	ensure_built()
	state = "loading"
	_clear_rows()
	status_l.visible = true
	status_l.text = tr("Loading the leaderboard…")

## Feed rows directly (the server reply, or a test's mock entries). Entries: {rank?, name, score, updated?, me?}.
func show_entries(list: Array, meta: Dictionary = {}) -> void:
	ensure_built()
	state = "rows" if not list.is_empty() else "empty"
	entries = list.duplicate(true)
	if not meta.is_empty(): you = meta.get("you", you) if meta.get("you") is Dictionary else you
	_clear_rows()
	if entries.is_empty():
		show_empty()
		return
	status_l.visible = false
	var me_name := api.user() if api != null else ""
	for i in entries.size():
		var e: Dictionary = entries[i] if entries[i] is Dictionary else {}
		var mine := bool(e.get("me", false)) or (me_name != "" and str(e.get("name", "")).to_lower() == me_name.to_lower())
		rows.add_child(_row(i + 1, e, mine))

func show_empty() -> void:
	ensure_built()
	state = "empty"
	_clear_rows()
	status_l.visible = true
	status_l.text = tr("No scores yet. Play a match to be the first!")

func show_error(msg: String) -> void:
	ensure_built()
	state = "error"
	_clear_rows()
	status_l.visible = true
	status_l.text = msg if msg != "" else tr("Couldn't load the leaderboard.")

## The rows currently on screen (tests / the title redesign may read them).
func row_count() -> int:
	return rows.get_child_count() if rows != null else 0

# ============================== rows ==============================

func _clear_rows() -> void:
	if rows == null: return
	for c in rows.get_children():
		rows.remove_child(c)
		c.queue_free()

func _row(rank: int, e: Dictionary, mine: bool) -> Control:
	var h := HBoxContainer.new()
	h.name = "Row%d" % rank
	h.add_theme_constant_override("separation", UiTheme.SP_2)
	h.custom_minimum_size = Vector2(0, ROW_H)
	var box: Control = h
	if mine:
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", UiTheme.box(Color(1, 0.812, 0.353, 0.13), 10, Color(1, 0.812, 0.353, 0.55), 2, 0))
		p.add_child(h)
		box = p
	_piece(h, str(e.get("rank", rank)), 54, HORIZONTAL_ALIGNMENT_LEFT, mine)
	var nm := str(e.get("name", "Player"))
	_piece(h, (nm + tr(" (you)")) if mine else nm, 0, HORIZONTAL_ALIGNMENT_LEFT, mine)
	_piece(h, str(int(e.get("score", 0))), 90, HORIZONTAL_ALIGNMENT_RIGHT, mine)
	_piece(h, _ago(int(e.get("updated", 0))), 110, HORIZONTAL_ALIGNMENT_RIGHT, false)
	return box

func _piece(box: Control, text: String, width: int, align: int, mine: bool) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 19)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.horizontal_alignment = align
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if width > 0: l.custom_minimum_size = Vector2(width, 0)
	else: l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if mine:
		l.add_theme_font_override("font", UiTheme.font(700))
		l.add_theme_color_override("font_color", UiTheme.ACCENT)
	box.add_child(l)
	return l

static func _ago(ms: int) -> String:
	if ms <= 0: return ""
	var s := Time.get_unix_time_from_system() - ms / 1000.0
	if s < 0.0: s = 0.0
	return AccountApi.ago(s)
