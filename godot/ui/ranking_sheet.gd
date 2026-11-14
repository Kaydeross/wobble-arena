class_name RankingSheet
extends Control
## The leaderboard sheet: a themed card with board tabs (K.O.s / Wins / Arcade co-op), the top entries (rank, name,
## score, when it was set), the signed-in player's own record even when it is below the shown top N, and a header that
## names the server (ui/server_badge.gd + ServerInfo) plus the Kids-mode note (no scores are sent in Kids mode).
##
## Every state says what is happening in plain words and offers the action that helps:
##   loading           "Loading the leaderboard…"
##   rows / empty      the board, or "No scores on <board> yet — be the first: play a match while signed in."
##   unsupported       the server build has no leaderboards (GET /api/rank 404: a JSON {err:"none"} or an old server's
##                     plain "not found"): "This server is running an older build without leaderboards…" + Retry;
##                     the raw server text is never shown (AccountApi.rank_failure classifies it)
##   offline           no network / no answer + Retry
##   error             anything else + Retry
##   signed out        a sign-in note in the "you" row + a Sign in button (the Account sheet behind this one)
##   signed in, no row "You're not on the <board> board yet. Sync your score…" + Sync my score
## "Sync my score" sends the same career totals as the automatic submit after a match (AccountApi.rank_stats) and shows
## the reply's board, so a score the old build missed still reaches the server.
##
## It is opened from the Account sheet's Leaderboard button (ui/account_sheet.gd). Data: AccountApi.fetch_rank /
## submit_rank (docs/PROTOCOL.md 4.1). This file owns no network calls itself: `api` is injected (Save.cloud by default),
## which also lets the headless test feed mock entries with show_entries() and fake failures with show_failure().

signal closed
signal account_requested             ## the "Sign in" action: the Account sheet behind this one is what the player needs

const BOARDS := [["kos", "K.O.s"], ["wins", "Wins"], ["arcade", "Arcade"]]
const ROW_H := 46.0
const LIST_H := 300.0                ## tallest rows area; short screens get a smaller one (_layout)
const CARD_W := 580.0
const LIMIT := 20
const BTN_H := 56.0                  ## touch target (canvas px: 44 pt at the designed scale)
const KIDS_NOTE := "Kids mode is on: scores are not sent to the leaderboard."
const FOOT := "Scores you set while signed in. Arcade ranks the furthest stage, weighted by difficulty."

var api: AccountApi
var board := "kos"
var state := "idle"                  ## idle | loading | rows | empty | error | unsupported | offline
var entries: Array = []
var you := {}                        ## the server's `you` row for the last fetch ({} = guest / unknown)
var kids := false
var card: PanelContainer
var badge: ServerBadge
var title_l: Label
var host_l: Label
var note_l: Label
var status_l: Label
var status_box: VBoxContainer
var retry_b: Button
var table_card: PanelContainer
var col_head: HBoxContainer
var rows: VBoxContainer
var scroll: ScrollContainer
var tabs := {}                       ## board id -> Button
var you_box: PanelContainer
var you_l: Label
var you_hint_l: Label
var sync_b: Button
var sign_in_b: Button
var sync_msg_l: Label
var foot_l: Label
var _built := false
var _syncing := false
var _sync_msg := ""                  ## a one-line answer to the last Sync ("" = the default hint)
var _sign_in_needed := false         ## the server said the login is no longer valid
var canvas_size_override := Vector2.ZERO   ## tests: pretend the canvas is this size (headless windows do not resize)

func _init() -> void:
	name = "Ranking"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false

func _ready() -> void:
	ensure_built()
	if api == null and is_inside_tree():
		var sv := get_tree().root.get_node_or_null("Save")
		if sv: api = sv.cloud
	if is_inside_tree():
		get_viewport().size_changed.connect(_layout)

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
	box.add_theme_constant_override("separation", UiTheme.SP_2)
	card.add_child(box)

	# header: title, the server chip, Close
	var head := HBoxContainer.new()
	head.name = "Head"
	head.add_theme_constant_override("separation", UiTheme.SP_3)
	box.add_child(head)
	title_l = Label.new()
	title_l.name = "Title"
	title_l.text = tr("Leaderboard")
	title_l.theme_type_variation = &"TitleLabel"
	title_l.add_theme_font_size_override("font_size", 28)
	title_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(title_l)
	badge = ServerBadge.new()
	badge.name = "ServerBadge"
	head.add_child(badge)
	var close_b := Button.new()
	close_b.name = "Close"
	close_b.text = tr("Close")
	close_b.custom_minimum_size = Vector2(104, BTN_H)
	close_b.add_theme_font_size_override("font_size", 19)
	close_b.pressed.connect(close)
	head.add_child(close_b)

	host_l = Label.new()
	host_l.name = "ServerLine"
	host_l.theme_type_variation = &"MutedLabel"
	host_l.add_theme_font_size_override("font_size", 15)
	host_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	host_l.clip_text = true
	box.add_child(host_l)

	# board tabs: always usable, the selected board is remembered through errors/retries
	var bar := HBoxContainer.new()
	bar.name = "Boards"
	bar.add_theme_constant_override("separation", UiTheme.SP_3)
	box.add_child(bar)
	for pair: Array in BOARDS:
		var b := Button.new()
		b.name = str(pair[0]).capitalize()
		b.text = tr(str(pair[1]))
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(0, BTN_H)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 20)
		b.pressed.connect(_pick.bind(str(pair[0])))
		bar.add_child(b)
		tabs[str(pair[0])] = b

	note_l = Label.new()
	note_l.name = "KidsNote"
	note_l.theme_type_variation = &"MutedLabel"
	note_l.add_theme_font_size_override("font_size", 16)
	note_l.add_theme_color_override("font_color", UiTheme.WARN)
	note_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note_l.text = tr(KIDS_NOTE)
	note_l.visible = false
	box.add_child(note_l)

	# the board: column heads, the rows (their own scroll) and the status/action area for every non-rows state
	table_card = PanelContainer.new()
	table_card.name = "Table"
	var ts := UiTheme.box(Color(0.02, 0.06, 0.08, 0.45), 12, Color(1, 1, 1, 0.12), 2, 0)
	ts.content_margin_left = 12; ts.content_margin_right = 12; ts.content_margin_top = 8; ts.content_margin_bottom = 8
	table_card.add_theme_stylebox_override("panel", ts)
	box.add_child(table_card)
	var tbox := VBoxContainer.new()
	tbox.name = "TableBox"
	tbox.add_theme_constant_override("separation", UiTheme.SP_2)
	table_card.add_child(tbox)

	col_head = HBoxContainer.new()
	col_head.name = "ColumnHeads"
	col_head.add_theme_constant_override("separation", UiTheme.SP_2)
	tbox.add_child(col_head)
	for pair: Array in [["#", 48, false], ["Player", 0, true], ["Score", 100, false], ["Updated", 118, false]]:
		var l := Label.new()
		l.text = tr(str(pair[0]))
		l.theme_type_variation = &"MutedLabel"
		l.add_theme_font_size_override("font_size", 15)
		if int(pair[1]) > 0: l.custom_minimum_size = Vector2(int(pair[1]), 0)
		if bool(pair[2]): l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if str(pair[0]) in ["Score", "Updated"] else HORIZONTAL_ALIGNMENT_LEFT
		col_head.add_child(l)

	scroll = ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.custom_minimum_size = Vector2(0, LIST_H)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tbox.add_child(scroll)
	rows = VBoxContainer.new()
	rows.name = "Rows"
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 2)
	scroll.add_child(rows)

	status_box = VBoxContainer.new()
	status_box.name = "StatusBox"
	status_box.add_theme_constant_override("separation", UiTheme.SP_2)
	tbox.add_child(status_box)
	status_l = Label.new()
	status_l.name = "Status"
	status_l.theme_type_variation = &"MutedLabel"
	status_l.add_theme_font_size_override("font_size", 18)
	status_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_l.custom_minimum_size = Vector2(0, 24)
	status_box.add_child(status_l)
	var retry_row := HBoxContainer.new()
	retry_row.name = "RetryRow"
	retry_row.alignment = BoxContainer.ALIGNMENT_CENTER
	status_box.add_child(retry_row)
	retry_b = Button.new()
	retry_b.name = "Retry"
	retry_b.text = tr("Retry")
	retry_b.theme_type_variation = &"PrimaryButton"
	retry_b.custom_minimum_size = Vector2(180, BTN_H)
	retry_b.add_theme_font_size_override("font_size", 20)
	retry_b.visible = false
	retry_b.pressed.connect(_on_retry)
	retry_row.add_child(retry_b)

	# the player's own record even when it is below the shown top N (or why there is none yet)
	you_box = PanelContainer.new()
	you_box.name = "You"
	you_box.add_theme_stylebox_override("panel", UiTheme.box(Color(1, 0.812, 0.353, 0.10), 12, Color(1, 0.812, 0.353, 0.45), 2, 0))
	you_box.visible = false
	box.add_child(you_box)
	var ybox := VBoxContainer.new()
	ybox.name = "YouBox"
	ybox.add_theme_constant_override("separation", UiTheme.SP_1)
	you_box.add_child(ybox)
	you_l = Label.new()
	you_l.name = "YouLine"
	you_l.add_theme_font_size_override("font_size", 19)
	you_l.add_theme_font_override("font", UiTheme.font(700))
	you_l.add_theme_color_override("font_color", UiTheme.ACCENT)
	you_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	you_l.visible = false
	ybox.add_child(you_l)
	you_hint_l = Label.new()
	you_hint_l.name = "YouHint"
	you_hint_l.theme_type_variation = &"MutedLabel"
	you_hint_l.add_theme_font_size_override("font_size", 16)
	you_hint_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	you_hint_l.visible = false
	ybox.add_child(you_hint_l)

	# footer actions: Sync my score (disabled + explained when it can't work), Sign in, the one-line answer
	var actions := HBoxContainer.new()
	actions.name = "Actions"
	actions.add_theme_constant_override("separation", UiTheme.SP_3)
	box.add_child(actions)
	sync_b = Button.new()
	sync_b.name = "Sync"
	sync_b.text = tr("Sync my score")
	sync_b.theme_type_variation = &"PrimaryButton"
	sync_b.custom_minimum_size = Vector2(200, BTN_H)
	sync_b.add_theme_font_size_override("font_size", 19)
	sync_b.pressed.connect(sync_score)
	actions.add_child(sync_b)
	sign_in_b = Button.new()
	sign_in_b.name = "SignIn"
	sign_in_b.text = tr("Sign in")
	sign_in_b.custom_minimum_size = Vector2(128, BTN_H)
	sign_in_b.add_theme_font_size_override("font_size", 19)
	sign_in_b.visible = false
	sign_in_b.pressed.connect(func() -> void: account_requested.emit())
	actions.add_child(sign_in_b)
	sync_msg_l = Label.new()
	sync_msg_l.name = "SyncMsg"
	sync_msg_l.theme_type_variation = &"MutedLabel"
	sync_msg_l.add_theme_font_size_override("font_size", 15)
	sync_msg_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sync_msg_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sync_msg_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	actions.add_child(sync_msg_l)

	foot_l = Label.new()
	foot_l.name = "Foot"
	foot_l.theme_type_variation = &"MutedLabel"
	foot_l.add_theme_font_size_override("font_size", 14)
	foot_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	foot_l.text = tr(FOOT)
	box.add_child(foot_l)
	if is_inside_tree(): _layout()

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
	_sign_in_needed = false
	_sync_msg = ""
	if badge != null:
		badge.setup("")
		var inf := ServerInfo.classify("")
		host_l.text = tr("Scores from %s · %s") % [tr(str(inf["label"])), str(inf["host"])]
	visible = true
	_sync_tabs()
	_layout()
	if fetch_now: refresh()
	else: show_loading()
	if _pc():
		(tabs[board] as Button).grab_focus.call_deferred()

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
	_sync_msg = ""
	_sync_tabs()
	refresh()

func _sync_tabs() -> void:
	for k: String in tabs:
		(tabs[k] as Button).set_pressed_no_signal(k == board)

# ============================== data ==============================

## Ask the server for the current board (AccountApi.fetch_rank) and show its rows.
func refresh() -> void:
	if api == null and is_inside_tree():
		var sv := get_tree().root.get_node_or_null("Save")
		if sv: api = sv.cloud
	kids = AccountApi.kids_mode()
	note_l.visible = kids
	_sync_msg = ""
	_sign_in_needed = false
	_layout()
	if api == null:
		show_failure({"ok": false, "status": 0, "err": "net"})
		return
	you = {}
	show_loading()
	var want_board := board
	api.fetch_rank(board, func(r: Dictionary) -> void:
		if not visible or board != want_board: return          # a slow reply for a board the player left: ignore
		if not bool(r.get("ok", false)):
			show_failure(r)
			return
		you = r.get("you") if r.get("you") is Dictionary else {}
		var list: Array = r.get("entries") if r.get("entries") is Array else []
		if list.is_empty(): show_empty()
		else: show_entries(list, {"you": you}))

func show_loading() -> void:
	ensure_built()
	state = "loading"
	entries = []
	you = {}
	_clear_rows()
	scroll.visible = false
	col_head.visible = false
	status_box.visible = true
	status_l.text = tr("Loading the leaderboard…")
	retry_b.visible = false
	_update_you()
	_update_actions()
	_layout()

## Feed rows directly (the server reply, or a test's mock entries). Entries: {rank?, name, score, updated?, me?};
## meta {"you": {rank, score, estimated?}}.
func show_entries(list: Array, meta: Dictionary = {}) -> void:
	ensure_built()
	entries = list.duplicate(true)
	if not meta.is_empty():
		var y: Variant = meta.get("you")
		if y is Dictionary: you = y
	if entries.is_empty():
		show_empty()
		return
	state = "rows"
	_clear_rows()
	status_box.visible = false
	retry_b.visible = false
	scroll.visible = true
	col_head.visible = true
	var me_name := api.user() if api != null else ""
	for i in entries.size():
		var e: Dictionary = entries[i] if entries[i] is Dictionary else {}
		var mine := bool(e.get("me", false)) or (me_name != "" and str(e.get("name", "")).to_lower() == me_name.to_lower())
		rows.add_child(_row(i + 1, e, mine))
	_update_you()
	_update_actions()
	_layout()

func show_empty() -> void:
	ensure_built()
	state = "empty"
	entries = []
	_clear_rows()
	scroll.visible = false
	col_head.visible = false
	status_box.visible = true
	status_l.text = tr("No scores on %s yet — be the first: play a match while signed in.") % _board_name()
	retry_b.visible = false
	_update_you()
	_update_actions()
	_layout()

func show_error(msg: String) -> void:
	ensure_built()
	state = "error"
	entries = []
	you = {}
	_clear_rows()
	scroll.visible = false
	col_head.visible = false
	status_box.visible = true
	status_l.text = msg if msg != "" else tr(AccountApi.RANK_ERROR_MSG)
	retry_b.visible = true
	_update_you()
	_update_actions()
	_layout()

## An old server (no /api/rank): explain it, never print the raw "Not found." body.
func show_unsupported() -> void:
	show_failure({"ok": false, "status": 404, "err": "none", "json": true})

## No network / no answer.
func show_offline() -> void:
	show_failure({"ok": false, "status": 0, "err": "net", "json": false})

## Turn any failed fetch/submit reply into the right state + action (AccountApi.rank_failure does the classification).
func show_failure(r: Dictionary) -> void:
	ensure_built()
	var f := AccountApi.rank_failure(r)
	var kind := str(f.get("kind", "error"))
	state = kind if kind in ["unsupported", "offline"] else "error"
	entries = []
	you = {}
	_sign_in_needed = kind == "auth"
	_clear_rows()
	scroll.visible = false
	col_head.visible = false
	status_box.visible = true
	status_l.text = str(f.get("msg", AccountApi.RANK_ERROR_MSG))
	retry_b.visible = bool(f.get("retry", true))
	_update_you()
	_update_actions()
	_layout()

## Send this device's career totals (the same payload the match-result auto-submit sends) and show the reply's board.
## The button is disabled with an explanation when signed out or in Kids mode; this repeats those guards for callers.
func sync_score() -> void:
	ensure_built()
	if _syncing: return
	if api == null:
		_sync_msg = tr("Can't reach the server right now. Try again in a moment.")
		_update_actions(); return
	if kids:
		_sync_msg = tr("Kids mode is on: scores are not sent to the leaderboard.")
		_update_actions(); return
	if not api.signed_in():
		_sync_msg = tr("Sign in on the Account screen to submit your score.")
		_update_actions(); return
	var st := AccountApi.rank_stats(_profile())
	if st.is_empty():
		_sync_msg = tr("No career totals to send yet — play a match first.")
		_update_actions(); return
	_syncing = true
	_sync_msg = tr("Sending your score…")
	_update_actions()
	var want_board := board
	var cb := func(r: Dictionary) -> void: _on_sync_done(r, want_board)
	api.submit_rank(st, cb, want_board)

func _on_sync_done(r: Dictionary, want_board: String) -> void:
	_syncing = false
	if not visible: return
	if bool(r.get("ok", false)):
		_sync_msg = ""
		if r.get("you") is Dictionary: you = r.get("you")
		if board == want_board:
			var list: Array = r.get("entries") if r.get("entries") is Array else []
			if list.is_empty(): show_empty()
			else: show_entries(list, {"you": you})
		if not you.is_empty() and int(you.get("score", 0)) > 0:
			_sync_msg = tr("Score sent — you're #%d on this board.") % int(you.get("rank", 0))
		else:
			_sync_msg = tr("Score sent.")
		_update_actions()
		_layout()
		return
	var f := AccountApi.rank_failure(r)
	var kind := str(f.get("kind", "error"))
	_sync_msg = str(f.get("msg", AccountApi.RANK_ERROR_MSG))
	if kind == "auth": _sign_in_needed = true
	if kind == "unsupported":
		show_failure(r)                                        # the board can never load: say why + offer Retry
	else:
		_update_you()
		_update_actions()
		_layout()

func _on_retry() -> void:
	_sync_msg = ""
	_sign_in_needed = false
	refresh()

## The rows currently on screen (tests / the title redesign may read them).
func row_count() -> int:
	return rows.get_child_count() if rows != null else 0

## The player's own line ("You — #12 · 340 K.O.s") when it is shown below the table, or "".
func you_text() -> String:
	return you_l.text if you_l != null and you_l.visible else ""

## The hint below the table (signed out / not on the board yet), or "".
func hint_text() -> String:
	return you_hint_l.text if you_hint_l != null and you_hint_l.visible else ""

# ============================== layout ==============================

## Fit the card to the canvas: full width on a phone, and a rows area that leaves room for the status, "you" row,
## actions and the wrapped footer at every supported size (the footer used to be cut off on short screens).
func _layout() -> void:
	if card == null: return
	var vp := canvas_size_override
	if vp == Vector2.ZERO:
		vp = get_viewport_rect().size if is_inside_tree() else Vector2(1170, 540)
	card.custom_minimum_size.x = minf(CARD_W, maxf(380.0, vp.x - 56.0))
	var reserved := 400.0
	if kids and note_l != null and note_l.visible: reserved += 26.0
	if scroll != null:
		scroll.custom_minimum_size = Vector2(0, clampf(vp.y - reserved, 100.0, LIST_H))

# ============================== "you" + actions ==============================

func _signed_in() -> bool:
	return api != null and api.signed_in()

## A PC desktop gets keyboard/controller focus on the selected tab. Read through the Tier autoload dynamically: the
## headless --script tests load class scripts before the autoload singletons are registered, so a direct `Tier` name
## would not compile there.
func _pc() -> bool:
	if not is_inside_tree(): return false
	var tier := get_tree().root.get_node_or_null("Tier")
	return tier != null and bool(tier.call("is_pc"))

func _profile() -> Node:
	if not is_inside_tree(): return null
	return get_tree().root.get_node_or_null("Save")

func _board_name() -> String:
	for pair: Array in BOARDS:
		if str(pair[0]) == board: return tr(str(pair[1]))
	return tr("K.O.s")

func _unit() -> String:
	match board:
		"wins": return tr("wins")
		"arcade": return tr("Arcade score")
	return tr("K.O.s")

func _you_in_entries() -> bool:
	var me_name := api.user().to_lower() if api != null else ""
	for e: Variant in entries:
		if not (e is Dictionary): continue
		if bool((e as Dictionary).get("me", false)): return true
		if me_name != "" and str((e as Dictionary).get("name", "")).to_lower() == me_name: return true
	return false

## The own-record row under the table: the server's `you` when it is below the shown top N, or the reason there is no
## row yet (signed out / no score on this board). An in-table row is already highlighted, so the pill stays hidden then.
func _update_you() -> void:
	if you_box == null: return
	you_box.visible = false
	you_l.visible = false
	you_hint_l.visible = false
	if kids:
		return
	if not _signed_in():
		you_box.visible = true
		you_hint_l.visible = true
		you_hint_l.add_theme_color_override("font_color", UiTheme.MUTED)
		you_hint_l.text = tr("Sign in on the Account screen to submit and see your rank.")
		return
	if state in ["rows", "empty"]:
		var in_rows := _you_in_entries()
		var score := int(you.get("score", 0))
		if not you.is_empty() and score > 0 and not in_rows:
			you_box.visible = true
			you_l.visible = true
			you_l.text = tr("You — #%d · %s%s") % [int(you.get("rank", 0)), "%s %s" % [_comma(score), _unit()],
				tr(" · estimated") if bool(you.get("estimated", false)) else ""]
		elif not in_rows:
			you_box.visible = true
			you_hint_l.visible = true
			you_hint_l.add_theme_color_override("font_color", UiTheme.MUTED)
			you_hint_l.text = tr("You're not on the %s board yet. Sync your score to appear on it.") % _board_name()

## Sync/Sign in availability + its one-line explanation (disabled when signed out or in Kids mode, never silent).
func _update_actions() -> void:
	if sync_b == null: return
	var signed := _signed_in()
	sync_b.disabled = _syncing or api == null or kids or not signed
	sign_in_b.visible = not signed or _sign_in_needed
	var hint := _sync_msg
	if hint == "":
		if api == null: hint = tr("Can't reach the server right now.")
		elif kids: hint = tr("Kids mode is not ranked.")
		elif not signed: hint = tr("Sign in to submit your score.")
		elif _sign_in_needed: hint = tr("Sign in again to submit your score.")
		elif _syncing: hint = tr("Sending your score…")
	sync_msg_l.text = hint

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
	_piece(h, str(int(e.get("rank", rank))), 48, HORIZONTAL_ALIGNMENT_LEFT, mine)   # JSON numbers arrive as float
	var nm := str(e.get("name", tr("Player")))
	_piece(h, (nm + tr(" (you)")) if mine else nm, 0, HORIZONTAL_ALIGNMENT_LEFT, mine)
	_piece(h, _comma(int(e.get("score", 0))), 100, HORIZONTAL_ALIGNMENT_RIGHT, mine)
	_piece(h, _ago(int(e.get("updated", 0))), 118, HORIZONTAL_ALIGNMENT_RIGHT, false)
	return box

func _piece(box: Control, text: String, width: int, align: int, mine: bool) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 19)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.horizontal_alignment = align
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.tooltip_text = text
	if width > 0: l.custom_minimum_size = Vector2(width, 0)
	else: l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if mine:
		l.add_theme_font_override("font", UiTheme.font(700))
		l.add_theme_color_override("font_color", UiTheme.ACCENT)
	box.add_child(l)
	return l

## 1234 -> "1,234".
static func _comma(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out

static func _ago(ms: int) -> String:
	if ms <= 0: return ""
	var s := Time.get_unix_time_from_system() - ms / 1000.0
	if s < 0.0: s = 0.0
	return AccountApi.ago(s)
