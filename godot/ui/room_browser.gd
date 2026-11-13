class_name RoomBrowser
extends VBoxContainer
## The public room list in the Play online panel (net/room_list.gd asks the relay, like the web game's Browse page):
## a header ("Public rooms", how many are open, Refresh) and a phone-style list (DragScroll) with a row per room:
## name, host, game type, arena, players n / max, playing or in the lobby. Tap a row to join it. Rooms that cannot be
## joined (another game version, full) are greyed out and say why. States: loading ("Looking for rooms…"), empty
## ("No rooms yet: host one" with a Host a room button), error (the server is unreachable, with Try again).
## Refreshes when it is shown and when Refresh is pressed. Private rooms never show here: "Join with code" is next to it.

signal join_requested(id: String)
signal host_requested

const ROW_H := 66.0                ## canvas px: over 44 pt on an iPhone in landscape

var list := RoomList.new()
var url := ""                     ## the relay WebSocket (main sets it from Settings `server_url` before refresh)
var auto_refresh := true          ## ask the relay whenever the list is shown (layout tests turn it off and fill it by hand)
var state := "idle"               ## idle | loading | rooms | empty | error
var rooms: Array = []
var head_l: Label
var count_l: Label
var refresh_b: Button
var scroll: DragScroll
var rows: VBoxContainer
var rows_by_id := {}              ## room id -> row Button
var msg_l: Label                  ## the loading / empty / error line
var action_b: Button              ## Host a room (empty) / Try again (error)

func _init() -> void:
	name = "Rooms"
	add_theme_constant_override("separation", 6)
	size_flags_horizontal = SIZE_EXPAND_FILL
	size_flags_vertical = SIZE_EXPAND_FILL

func _ready() -> void:
	var head := HBoxContainer.new()
	head.name = "Head"
	head.add_theme_constant_override("separation", 10)
	add_child(head)
	head_l = Label.new()
	head_l.name = "Title"
	head_l.text = "Public rooms"
	head_l.add_theme_font_size_override("font_size", 22)
	head_l.add_theme_font_override("font", UiTheme.font(700))
	head_l.size_flags_vertical = SIZE_SHRINK_CENTER
	head.add_child(head_l)
	count_l = Label.new()
	count_l.name = "Count"
	count_l.theme_type_variation = &"MutedLabel"
	count_l.add_theme_font_size_override("font_size", 16)
	count_l.size_flags_horizontal = SIZE_EXPAND_FILL
	count_l.size_flags_vertical = SIZE_SHRINK_CENTER
	count_l.clip_text = true
	count_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.add_child(count_l)
	refresh_b = Button.new()
	refresh_b.name = "Refresh"
	refresh_b.text = "Refresh"
	refresh_b.custom_minimum_size = Vector2(124, 62)
	refresh_b.add_theme_font_size_override("font_size", 18)
	refresh_b.pressed.connect(refresh)
	head.add_child(refresh_b)
	scroll = DragScroll.new()
	scroll.name = "Scroll"
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, ROW_H * 1.6)
	add_child(scroll)
	rows = VBoxContainer.new()
	rows.name = "List"
	rows.size_flags_horizontal = SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 6)
	scroll.add_child(rows)
	list.done.connect(_on_done)
	_show_message("Looking for rooms…", "")

func _process(dt: float) -> void:
	if list.busy: list.poll(dt)

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and auto_refresh and is_inside_tree() and is_visible_in_tree() and not list.busy:
		refresh.call_deferred()

## Ask the relay again (the list keeps showing until the answer comes, unless it is empty).
func refresh() -> void:
	if list.busy or not is_inside_tree(): return
	state = "loading"
	refresh_b.disabled = true
	count_l.text = "Looking for rooms…"
	if rooms.is_empty(): _show_message("Looking for rooms…", "")
	list.fetch(url)

func _on_done(r: Array, err: String) -> void:
	show_rooms(r, err)

## Fill the list (tests call this with a mock list or an error).
func show_rooms(r: Array, err: String = "") -> void:
	refresh_b.disabled = false
	if err != "":
		state = "error"
		rooms = []
		count_l.text = "Offline"
		_show_message(err, "Try again")
		return
	rooms = r
	if r.is_empty():
		state = "empty"
		count_l.text = "None open yet"
		_show_message("No rooms yet: host one, or join a friend with a code. Be the first!", "Host a room")
		return
	state = "rooms"
	var playing := 0
	for x: Dictionary in r: playing += int(x.get("n", 0))
	count_l.text = (tr("%d open · %d playing") % [r.size(), playing]) if r.size() != 1 else (tr("1 open · %d playing") % playing)
	_clear()
	for x: Dictionary in r: rows.add_child(_row(x))
	JuicyButton.attach_all(rows)

func _clear() -> void:
	for c in rows.get_children():
		rows.remove_child(c)
		c.queue_free()
	rows_by_id.clear()
	msg_l = null
	action_b = null

func _show_message(text: String, action: String) -> void:
	_clear()
	var box := VBoxContainer.new()
	box.name = "Message"
	box.add_theme_constant_override("separation", 10)
	box.size_flags_horizontal = SIZE_EXPAND_FILL
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	rows.add_child(box)
	msg_l = Label.new()
	msg_l.name = "Text"
	msg_l.text = text
	msg_l.theme_type_variation = &"MutedLabel"
	msg_l.add_theme_font_size_override("font_size", 18)
	msg_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg_l.custom_minimum_size = Vector2(0, 30)
	box.add_child(msg_l)
	if action != "":
		action_b = Button.new()
		action_b.name = "Action"
		action_b.text = action
		action_b.custom_minimum_size = Vector2(220, 62)
		action_b.size_flags_horizontal = SIZE_SHRINK_CENTER
		action_b.add_theme_font_size_override("font_size", 19)
		if action == "Host a room":
			action_b.theme_type_variation = &"PrimaryButton"
			action_b.pressed.connect(func() -> void: host_requested.emit())
		else:
			action_b.pressed.connect(refresh)
		box.add_child(action_b)

## One room: name and players on the first line, host · game type · arena · playing / in the lobby (or why it cannot
## be joined) under it.
func _row(r: Dictionary) -> Button:
	var why := RoomList.blocked_reason(r)
	var b := Button.new()
	b.name = "Room_" + str(r["id"]).validate_node_name()
	b.set_meta("room", str(r["id"]))
	b.custom_minimum_size = Vector2(0, ROW_H)
	b.disabled = why != ""
	b.focus_mode = Control.FOCUS_ALL
	b.tooltip_text = (tr("Join %s") % str(r["name"])) if why == "" else tr(why)
	b.pressed.connect(func() -> void: if not b.disabled: join_requested.emit(str(r["id"])))
	scroll.add_card(b)
	b.button_mask = MOUSE_BUTTON_MASK_LEFT if Tier.is_pc() else 0   # PC: a click on a row joins (the list handles touch)
	if why != "": b.modulate = Color(1, 1, 1, 0.5)
	var h := HBoxContainer.new()
	h.name = "Row"
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 14; h.offset_right = -14
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", 12)
	b.add_child(h)
	var v := VBoxContainer.new()
	v.name = "Info"
	v.size_flags_horizontal = SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	var n := Label.new()
	n.name = "Name"
	n.text = str(r["name"])
	n.add_theme_font_size_override("font_size", 20)
	n.add_theme_font_override("font", UiTheme.font(700))
	n.clip_text = true
	n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	n.set_meta("user_text", true)   # a player's room name: "…" when it is too long (the tooltip has it all)
	v.add_child(n)
	var parts: Array = []
	if str(r["host"]) != "": parts.append(tr("Host: %s") % str(r["host"]))
	if str(r["modeName"]) != "": parts.append(tr(str(r["modeName"])))
	if str(r["map"]) != "": parts.append(tr(str(r["map"])))
	parts.append(tr(why) if why != "" else (tr("Playing now") if r["started"] else tr("In the lobby")))
	var s := Label.new()
	s.name = "Sub"
	s.text = " · ".join(parts)
	s.theme_type_variation = &"MutedLabel"
	s.add_theme_font_size_override("font_size", 15)
	s.clip_text = true
	s.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if why != "": s.add_theme_color_override("font_color", UiTheme.ACCENT)
	v.add_child(s)
	var c := Label.new()
	c.name = "Players"
	c.text = "%d/%d" % [int(r["n"]), int(r["max"])]
	c.add_theme_font_size_override("font_size", 22)
	c.add_theme_font_override("font", UiTheme.font(700))
	c.size_flags_vertical = SIZE_SHRINK_CENTER
	h.add_child(c)
	rows_by_id[str(r["id"])] = b
	return b
