extends SceneTree
## Headless test: join a room on a local server and get welcomed by the host.
## Run by tools/test-godot.js:  godot --headless --path godot --script res://tests/join_test.gd -- ws://127.0.0.1:PORT/ws ROOMCODE

var net := NetClient.new()
var t := 0.0
var done := false

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("usage: -- URL ROOMCODE"); quit(2); return
	net.player_name = "GodotBot"
	net.connected.connect(func(): net.join_room(args[1]))
	net.join_failed.connect(func(r): print("FAIL nojoin ", r); quit(1))
	net.welcomed.connect(func(slot, name):
		print("WELCOMED slot=", slot, " room=", name); done = true; quit(0))
	net.connect_to_server(args[0])

func _process(dt: float) -> bool:
	net.poll()
	t += dt
	if t > 10.0 and not done:
		print("FAIL timeout"); quit(1)
	return false
