extends Control
## Title scene: offline play (map + class pickers) and a placeholder online panel: server address, room code, name,
## Join (as a guest, GuestSession) and a minimal login (POST /api/login, token kept in Settings). Real menus come in
## Phase 3. Command line (after `--`): --join=ROOM [--server=ws://host:3000/ws] [--name=NAME] joins straight away.

const WORLD := "res://world/world.tscn"
const OFFLINE_MAPS := ["arena", "practice"]

## Set by the world when it hands an active session back (host migration) and/or a message to show.
var session: GuestSession = null
var notice := ""

@onready var status: Label = $Status
@onready var map_pick: OptionButton = $Play/Map
@onready var class_pick: OptionButton = $Play/Class
var class_ids: Array = []
var _ui := {}
var _api: AccountApi

func _ready() -> void:
	for id in OFFLINE_MAPS:
		map_pick.add_item(str(Content.get_map(id).get("name", id)))
	var last := OFFLINE_MAPS.find(str(Settings.get_value("offline_map", "arena")))
	map_pick.select(maxi(last, 0))
	class_ids = Content.classes.keys()
	for cid in class_ids:
		class_pick.add_item(str(Content.get_class_data(cid).get("name", cid)))
	class_pick.select(maxi(class_ids.find(str(Settings.get_value("class", "wobbler"))), 0))
	$Play/PlayOffline.pressed.connect(play_offline)
	_api = AccountApi.new()
	add_child(_api)
	_api.finished.connect(func(_ok: bool, msg: String) -> void: status.text = msg; _refresh_login())
	_build_online()
	status.text = notice if notice != "" else "Play offline, or join a friend's room."
	if session != null:
		_bind_session()
		status.text = (notice + "  " if notice != "" else "") + session.status
	var join := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--join="): join = a.substr(7)
		elif a.begins_with("--server="): _ui["server"].text = a.substr(9)
		elif a.begins_with("--name="): _ui["name"].text = a.substr(7)
	if join != "" and session == null:
		_ui["room"].text = join
		join_room()

func _process(dt: float) -> void:
	if session != null:
		session.poll(dt)

func _line(parent: Node, placeholder: String, text: String, w: float) -> LineEdit:
	var l := LineEdit.new()
	l.placeholder_text = placeholder
	l.text = text
	l.custom_minimum_size = Vector2(w, 44)
	l.add_theme_font_size_override("font_size", 18)
	parent.add_child(l)
	return l

func _button(parent: Node, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(110, 44)
	b.add_theme_font_size_override("font_size", 18)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

func _build_online() -> void:
	var box := VBoxContainer.new()
	box.name = "Online"
	box.anchor_left = 0.5; box.anchor_right = 0.5; box.anchor_top = 0.5; box.anchor_bottom = 0.5
	box.offset_left = -470; box.offset_right = 470; box.offset_top = 120; box.offset_bottom = 250
	add_child(box)
	var r1 := HBoxContainer.new(); r1.alignment = BoxContainer.ALIGNMENT_CENTER; box.add_child(r1)
	_ui["server"] = _line(r1, "ws://server:3000/ws", str(Settings.get_value("server_url")), 300)
	_ui["room"] = _line(r1, "Room code", str(Settings.get_value("room_code", "")), 130)
	_ui["name"] = _line(r1, "Your name", str(Settings.get_value("name", "Player")), 150)
	_ui["join"] = _button(r1, "Join room", join_room)
	_ui["leave"] = _button(r1, "Leave", func() -> void: if session: session.leave("You left the room."))
	var r2 := HBoxContainer.new(); r2.alignment = BoxContainer.ALIGNMENT_CENTER; box.add_child(r2)
	_ui["user"] = _line(r2, "Username or email", str(Settings.get_value("user", "")), 220)
	_ui["pass"] = _line(r2, "Password", "", 180)
	(_ui["pass"] as LineEdit).secret = true
	_ui["login"] = _button(r2, "Log in", func() -> void:
		status.text = "Logging in…"
		_api.login(_ui["server"].text, _ui["user"].text, _ui["pass"].text))
	_ui["logout"] = _button(r2, "Log out", func() -> void: _api.logout(); status.text = "Logged out."; _refresh_login())
	_ui["acct"] = Label.new()
	_ui["acct"].add_theme_font_size_override("font_size", 16)
	r2.add_child(_ui["acct"])
	_ui["roster"] = Label.new()
	_ui["roster"].horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ui["roster"].add_theme_font_size_override("font_size", 16)
	box.add_child(_ui["roster"])
	_refresh_login()
	_refresh_buttons()

func _refresh_login() -> void:
	var u := str(Settings.get_value("user", ""))
	var logged := str(Settings.get_value("token", "")) != ""
	_ui["acct"].text = ("Logged in: " + u) if logged else "Not logged in"
	_ui["logout"].visible = logged

func _refresh_buttons() -> void:
	var on := session != null and session.is_active()
	_ui["join"].disabled = on
	_ui["leave"].visible = on
	if not on: _ui["roster"].text = ""

func join_room() -> void:
	if session != null and session.is_active(): return
	var url := str(_ui["server"].text).strip_edges()
	var room := str(_ui["room"].text).strip_edges()      # the server matches codes case-insensitively
	var nm := str(_ui["name"].text).strip_edges().substr(0, 12)
	if nm == "": nm = "Player"
	Settings.set_value("server_url", url); Settings.set_value("room_code", room); Settings.set_value("name", nm)
	if class_ids.size() > 0: Settings.set_value("class", class_ids[maxi(class_pick.selected, 0)])
	session = GuestSession.new()
	_bind_session()
	session.begin(url, room, {"name": nm, "skin": Settings.get_value("skin", "none"), "hat": Settings.get_value("hat", "none"),
		"color": Settings.get_value("color", 0x39b5a8), "cls": Settings.get_value("class", "wobbler")}, str(Settings.get_value("token", "")))
	_refresh_buttons()

func _bind_session() -> void:
	session.status_changed.connect(_on_status)
	session.ended.connect(_on_ended)
	session.roster_changed.connect(_on_roster)
	session.match_started.connect(_enter_match)
	_refresh_buttons()

func _unbind_session() -> void:
	session.status_changed.disconnect(_on_status)
	session.ended.disconnect(_on_ended)
	session.roster_changed.disconnect(_on_roster)
	session.match_started.disconnect(_enter_match)

func _on_status(t: String) -> void:
	status.text = t

func _on_ended(_reason: String) -> void:
	_unbind_session()
	session = null
	_refresh_buttons()

func _on_roster(r: Array) -> void:
	var names: Array = []
	for e: Dictionary in r: names.append(e["name"])
	_ui["roster"].text = "In the room: " + ", ".join(names)

## `start` from the host: into the match (the world takes the session over).
func _enter_match(s: Dictionary) -> void:
	if not is_inside_tree(): return
	_unbind_session()
	var world: Node = load(WORLD).instantiate()
	world.session = session
	world.start_msg = s
	session = null
	get_tree().change_scene_to_node.call_deferred(world)

func play_offline() -> void:
	if session != null: session.leave("")
	var id: String = OFFLINE_MAPS[maxi(map_pick.selected, 0)]
	Settings.set_value("offline_map", id)
	if class_ids.size() > 0:
		Settings.set_value("class", class_ids[maxi(class_pick.selected, 0)])
	var world: Node = load(WORLD).instantiate()
	world.map_id = id
	get_tree().change_scene_to_node(world)
