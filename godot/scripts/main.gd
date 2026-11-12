extends Control
## Skeleton scene: connects to the server, joins a room by code and shows the status. Real menus come later.

@export var server_url := "ws://127.0.0.1:3000/ws"
var net := NetClient.new()
@onready var status: Label = $Status

func _ready() -> void:
	net.connected.connect(func(): status.text = "Connected. Enter a room code.")
	net.disconnected.connect(func(): status.text = "Disconnected")
	net.join_failed.connect(func(r): status.text = "Could not join: " + r)
	net.welcomed.connect(func(slot, name): status.text = "In room \"%s\" as player %d" % [name, slot])
	status.text = "Connecting…"
	net.connect_to_server(server_url)

func _process(_dt: float) -> void:
	net.poll()
