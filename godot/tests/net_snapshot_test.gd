extends SceneTree
## NetSnapshot: `S` entries, `h` and `ko` survive a JSON round trip, and junk is rejected or clamped like the web game's
## netCleanHit / netGuard. godot --headless --path godot --script res://tests/net_snapshot_test.gd

var fails := 0
var checks := 0

func ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		print("FAIL ", what)

func wire(m: Dictionary) -> Variant:
	return JSON.parse_string(JSON.stringify(m))     # what actually travels

func _initialize() -> void:
	# --- S entry round trip ---
	var f := FighterState.new()
	f.net_slot = 3; f.yaw = 1.23456; f.hp = 87.5; f.lives = 2; f.invuln = 0.5; f.weapon = "smg"
	f.phys.px = 1.005; f.phys.py = -2.675; f.phys.pz = 10.12345; f.phys.vx = -0.004; f.phys.vy = 7.777; f.phys.vz = 0.0; f.phys.grounded = true
	f.arm_x = 0.6; f.arm_y = -0.8; f.arm_z = 0.0
	var e := NetSnapshot.encode_entry(f, {"pt": 12.5})
	ok(e["x"] == 1.0 and e["y"] == -2.67 and e["z"] == 10.12 and e["vx"] == 0.0 and e["vy"] == 7.78, "S rounding like toFixed(2): %s" % str(e))
	ok(e["hp"] == 88 and e["pt"] == 13 and e["iv"] == 1 and e["g"] == 1 and e["d"] == 0 and e["w"] == "smg", "S flags: %s" % str(e))
	var back := NetSnapshot.decode_state(wire(NetSnapshot.encode_state([e])))
	ok(back.size() == 1, "S decodes one entry")
	if back.size() == 1:
		var d: Dictionary = back[0]
		ok(d["id"] == 3 and d["x"] == 1.0 and d["y"] == -2.67 and d["z"] == 10.12 and d["yaw"] == 1.23 and d["ax"] == 0.6 and d["ay"] == -0.8, "S values: %s" % str(d))
		ok(d["w"] == "smg" and d["hp"] == 88.0 and d["iv"] == true and d["g"] == true and d["d"] == false and d["lv"] == 2 and d["pt"] == 13.0, "S fields: %s" % str(d))
	f.dead = true
	ok(NetSnapshot.encode_entry(f)["w"] == null and NetSnapshot.encode_entry(f)["d"] == 1, "dead -> w null")
	# --- S junk ---
	ok(NetSnapshot.decode_state({"t": "S", "l": "nope"}).is_empty(), "S without list")
	ok(NetSnapshot.decode_state({"t": "s", "l": []}).is_empty(), "wrong type")
	ok(NetSnapshot.decode_state(null).is_empty() and NetSnapshot.decode_state([1, 2]).is_empty(), "not an object")
	var junk := NetSnapshot.decode_state({"t": "S", "l": [5, null, {"id": 1, "x": "a", "y": 0, "z": 0}, {"id": 99, "x": 0, "y": 0, "z": 0},
		{"id": 2, "x": 1, "y": 2, "z": 3, "hp": "lots", "w": 7, "vx": 1e300}]})
	ok(junk.size() == 1 and junk[0]["id"] == 2 and junk[0]["hp"] == 0.0 and junk[0]["w"] == "" and junk[0]["vx"] == 1e6, "S junk entries dropped/cleaned: %s" % str(junk))
	var guarded := NetSnapshot.decode_state({"t": "S", "l": [{"id": 0, "x": 1, "y": 2, "z": 3}, {"id": 5, "x": 1, "y": 2, "z": 3}]}, 4)
	ok(guarded.size() == 1 and guarded[0]["id"] == 4, "guest S: own entry only, id forced to its slot")
	# --- h round trip ---
	var h := NetSnapshot.encode_hit(0, 5, 2, 12.345678, 0.12345, -0.5, 0.9876543, 7.777, true)
	ok(h["d"] == 12.35 and h["x"] == 0.123 and h["z"] == 0.988 and h["f"] == 7.78 and h["hd"] == 1, "h rounding: %s" % str(h))
	var hb := NetSnapshot.decode_hit(wire(h))
	ok(not hb.is_empty() and hb["vs"] == 5 and hb["from"] == 2 and hb["to"] == 0 and hb["d"] == 12.35 and hb["y"] == -0.5 and hb["hd"] == true, "h decode: %s" % str(hb))
	ok(NetSnapshot.decode_hit(wire(h), 2).size() > 0, "guest may claim its own hit")
	ok(NetSnapshot.decode_hit(wire(h), 3).is_empty(), "guest may not claim another slot's hit")
	var big := NetSnapshot.decode_hit({"t": "h", "vs": 1, "from": 0, "to": 1, "d": 1e9, "f": -3, "x": 9, "y": -9, "z": "x"})
	ok(big["d"] == 250.0 and big["f"] == 0.0 and big["x"] == 2.0 and big["y"] == -2.0 and big["z"] == 0.0, "h clamps d 0-250, f 0-120, dir +-2: %s" % str(big))
	var big2 := NetSnapshot.decode_hit({"t": "h", "vs": 1, "from": 0, "to": 1, "d": "40", "f": 500, "x": null, "y": true, "z": 1.5})
	ok(big2["d"] == 40.0 and big2["f"] == 120.0 and big2["x"] == 0.0 and big2["y"] == 1.0 and big2["z"] == 1.5, "h numeric strings / null / bool like +v: %s" % str(big2))
	ok(NetSnapshot.decode_hit({"t": "h", "vs": 42, "from": 0}).is_empty(), "h bad victim slot")
	ok(NetSnapshot.decode_hit({"t": "ko"}).is_empty() and NetSnapshot.decode_hit("h").is_empty(), "h wrong message")
	# --- ko ---
	var k := NetSnapshot.decode_ko(wire(NetSnapshot.encode_ko(1, 4)))
	ok(k["from"] == 1 and k["to"] == 4, "ko round trip")
	ok(NetSnapshot.decode_ko(wire(NetSnapshot.encode_ko(-1, 4)))["from"] == -1, "ko without killer")
	ok(NetSnapshot.decode_ko(wire(NetSnapshot.encode_ko(1, 4)), 4).size() > 0 and NetSnapshot.decode_ko(wire(NetSnapshot.encode_ko(1, 4)), 2).is_empty(), "guest may only report its own K.O.")
	ok(NetSnapshot.decode_ko({"t": "ko", "to": "x"}).size() > 0 and NetSnapshot.decode_ko({"t": "ko", "to": 77}).is_empty(), "ko slot range")
	# --- Combat sends h for a ghost victim ---
	var c := Combat.new()
	c.net_started = true
	var a := FighterState.new(); a.net_slot = 0; a.is_player = true
	var g := FighterState.new(); g.net_slot = 2; g.is_ghost = true; g.net_human = true
	var r := c.hit(g, 10.0, 0.0, 0.0, 1.0, 5.0, false, a)
	ok(r["applied"] and r["sent"]["to"] == 2 and r["sent"]["vs"] == 2 and g.hp == 200.0, "hit on a ghost is sent, not applied")
	c.dispose()
	print("NETSNAP checks=%d failures=%d" % [checks, fails])
	quit(0 if fails == 0 else 1)
