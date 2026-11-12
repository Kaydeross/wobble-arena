extends Control
## Title scene: connects to the server (status in the guest chip), shows the build label and starts the offline
## test world. Laid out with containers inside a safe-area MarginContainer so nothing overlaps at any aspect ratio
## (tests/ui_layout_test.gd checks 852x393, 1170x540, 1280x720 and 390x844).

const WORLD := "res://world/world.tscn"
const OFFLINE_MAPS := ["arena", "practice"]
const MARGIN := Vector4(28, 18, 28, 14)   ## left, top, right, bottom padding inside the safe area
const TIPS := [
	"Tip: push the stick to the edge to sprint.",
	"Tip: knock fighters off the edge for a K.O.",
	"Tip: crates drop weapons, heals and power-ups.",
	"Tip: kick and shove work even without a weapon.",
	"Tip: press F3 (or tap with three fingers) to show the FPS meter.",
]

@export var server_url := "ws://127.0.0.1:3000/ws"
var net := NetClient.new()
@onready var safe: MarginContainer = $Safe
@onready var status: Label = $Safe/Col/Top/GuestChip/Row/Status
@onready var dot: Panel = $Safe/Col/Top/GuestChip/Row/Dot
@onready var map_pick: OptionButton = $Safe/Col/Body/Picks/Box/MapRow/Map
@onready var class_pick: OptionButton = $Safe/Col/Body/Picks/Box/ClassRow/Class
@onready var fps_toggle: CheckButton = $Safe/Col/Body/Picks/Box/FpsRow/Fps
@onready var play: Button = $Safe/Col/Body/Play
var class_ids: Array = []

func _ready() -> void:
	net.connected.connect(func(): _status("Online", UiTheme.GOOD))
	net.disconnected.connect(func(): _status("Offline", UiTheme.MUTED))
	net.join_failed.connect(func(r): _status("Could not join: " + r, UiTheme.BAD))
	net.welcomed.connect(func(slot, name): _status("In \"%s\" (P%d)" % [name, slot], UiTheme.GOOD))
	_status("Connecting…", UiTheme.WARN)
	net.connect_to_server(server_url)
	for id in OFFLINE_MAPS:
		map_pick.add_item(str(Content.get_map(id).get("name", id)))
	var last := OFFLINE_MAPS.find(str(Settings.get_value("offline_map", "arena")))
	map_pick.select(maxi(last, 0))
	class_ids = Content.classes.keys()
	for cid in class_ids:
		class_pick.add_item(str(Content.get_class_data(cid).get("name", cid)))
	class_pick.select(maxi(class_ids.find(str(Settings.get_value("class", "wobbler"))), 0))
	play.pressed.connect(play_offline)
	fps_toggle.button_pressed = bool(Settings.get_value("show_fps", false))
	fps_toggle.toggled.connect(func(on: bool): Settings.set_value("show_fps", on))
	Settings.changed.connect(_on_setting)
	$Safe/Col/Tip.text = TIPS[randi() % TIPS.size()]
	JuicyButton.attach_all(self)
	get_viewport().size_changed.connect(apply_safe_area)
	apply_safe_area()
	if Tier.is_pc():
		play.grab_focus.call_deferred()   # keyboard / gamepad start on PLAY

func _on_setting(key: String, v: Variant) -> void:
	if key == "show_fps" and fps_toggle.button_pressed != bool(v):
		fps_toggle.set_pressed_no_signal(bool(v))

func _status(t: String, c: Color) -> void:
	status.text = t
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(5)
	dot.add_theme_stylebox_override("panel", sb)

## Safe-area insets (notch, home indicator) plus our own padding.
func apply_safe_area() -> void:
	var i := SafeArea.insets(get_viewport())
	safe.add_theme_constant_override("margin_left", int(MARGIN.x + i[0]))
	safe.add_theme_constant_override("margin_top", int(MARGIN.y + i[1]))
	safe.add_theme_constant_override("margin_right", int(MARGIN.z + i[2]))
	safe.add_theme_constant_override("margin_bottom", int(MARGIN.w + i[3]))

func play_offline() -> void:
	var id: String = OFFLINE_MAPS[maxi(map_pick.selected, 0)]
	Settings.set_value("offline_map", id)
	if class_ids.size() > 0:
		Settings.set_value("class", class_ids[maxi(class_pick.selected, 0)])
	net.close()
	var world: Node = load(WORLD).instantiate()
	world.map_id = id
	get_tree().change_scene_to_node(world)

func _process(_dt: float) -> void:
	net.poll()
