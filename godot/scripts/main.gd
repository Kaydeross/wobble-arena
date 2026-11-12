extends Control
## Title scene: connects to the server (status line), shows the build label and starts the offline test world.
## Real menus come later (Phase 3).

const WORLD := "res://world/world.tscn"
const OFFLINE_MAPS := ["arena", "practice"]

@export var server_url := "ws://127.0.0.1:3000/ws"
var net := NetClient.new()
@onready var status: Label = $Status
@onready var map_pick: OptionButton = $Play/Map

func _ready() -> void:
	net.connected.connect(func(): status.text = "Connected. Enter a room code.")
	net.disconnected.connect(func(): status.text = "Disconnected")
	net.join_failed.connect(func(r): status.text = "Could not join: " + r)
	net.welcomed.connect(func(slot, name): status.text = "In room \"%s\" as player %d" % [name, slot])
	status.text = "Connecting…"
	net.connect_to_server(server_url)
	for id in OFFLINE_MAPS:
		map_pick.add_item(str(Content.get_map(id).get("name", id)))
	var last := OFFLINE_MAPS.find(str(Settings.get_value("offline_map", "arena")))
	map_pick.select(maxi(last, 0))
	$Play/PlayOffline.pressed.connect(play_offline)

func play_offline() -> void:
	var id: String = OFFLINE_MAPS[maxi(map_pick.selected, 0)]
	Settings.set_value("offline_map", id)
	net.close()
	var world: Node = load(WORLD).instantiate()
	world.map_id = id
	get_tree().change_scene_to_node(world)

func _process(_dt: float) -> void:
	net.poll()
