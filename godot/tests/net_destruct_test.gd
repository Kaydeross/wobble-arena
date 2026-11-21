extends SceneTree
## Online breakable cover (docs/PROTOCOL.md 6.5, docs/DESTRUCTIBLE.md), in one process with no server: a real host World
## (HostSession + HostMatch) and real guest Worlds (GuestSession + NetMatch) whose sessions only record what they send, and
## the test carries the messages across. Run by tools/test-godot-destruct.js:
##   godot --headless --path godot --script res://tests/net_destruct_test.gd -- --no-save
## Proves: the rule is on only in an all-app room, every peer derives the same breakable set from `dseed`, a host break goes
## out as `brk` and the guest applies it (solid out, mesh hidden, the same `break` event -> debris), guests never decide a
## break (no hp, no `brk` sent, a forged `brk` at the host is dropped), respawn is host-authored (`brs`), a late joiner gets
## `brks` in its `start` (no debris), a host migration carries the list in `rsx.brks`, a web guest cannot join the room, and
## the broken sets never diverge.

class FakeHost:
	extends HostSession
	var out: Array = []        ## every message the room would have sent (send / _all)
	var direct: Array = []     ## [cid, message] sent to one guest
	func send(m: Dictionary) -> void: out.append(m)
	func _all(m: Dictionary, _except: int = 0) -> void: out.append(m)
	func _to(cid: int, m: Dictionary) -> void: direct.append([cid, m])
	func push_info() -> void: pass
	func _close_later(_cid: int) -> void: pass

class FakeGuest:
	extends GuestSession
	var out: Array = []
	func send(m: Dictionary) -> void: out.append(m)

var fails := 0
var checks := 0

func check(ok: bool, msg: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		print("FAIL ", msg)

func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _info(name: String, gd: bool) -> Dictionary:
	var i := {"name": name, "skin": "none", "hat": "none", "color": 0x39b5a8, "cls": "wobbler"}
	if gd: i["gd"] = NetClient.GD
	return i

func _host(web_guest: bool) -> FakeHost:
	var h := FakeHost.new()
	h.phase = GuestSession.Phase.LOBBY
	h.map_id = "arena"; h.want_mode = "classic"; h.mode_id = "classic"; h.opt_max = 4; h.opt_bots = true; h.bot_n = 4
	var me := _info("Host", true); me["id"] = 0
	var g := _info("Guest", not web_guest); g["id"] = 1
	h.roster = [me, g]
	h.conns = {1: 11}; h.cid_slot = {11: 1}
	return h

func _world(session: Object, start: Dictionary) -> Node:
	var w: Node = load("res://world/world.tscn").instantiate()
	w.session = session
	w.start_msg = start
	w.auto_run = false
	root.add_child(w)
	return w

func _ids(d: Destruct) -> Array:
	var out: Array = []
	for p: Dictionary in d.props: out.append(p["id"])
	return out

## What the host said since `from`, to the guest world (the relay does this in a real room).
func _deliver(host: FakeHost, from: int, guest_world: Node) -> int:
	var n := 0
	for k in range(from, host.out.size()):
		var m: Dictionary = host.out[k]
		if m.get("t") in ["brk", "brs"]:
			guest_world.net_match.handle(m.duplicate(true)); n += 1
	return n

func _run() -> void:
	# ---- the rule: on only when every peer is on the app ----
	var hw: FakeHost = _host(true)
	check(hw.start_match(), "web room starts")
	check(not (hw.start_msg["rules"] as Dictionary).has("dest"), "a web guest in the lobby: no rules.dest (the match is plain)")
	var host := _host(false)
	check(host.start_match(), "all-app room starts")
	var rules: Dictionary = host.start_msg["rules"]
	check(rules.get("dest") == true and rules.has("dseed") and rules.get("nz") == true, "all-app room: rules.dest + dseed + nz")
	var off := _host(false); off.opt_dest = false; off.start_match()
	check(not (off.start_msg["rules"] as Dictionary).has("dest"), "Host-sheet dest off: no rules.dest")
	var arc := _host(false); arc.mode_id = "construction"; arc.want_mode = "construction"; arc.map_id = "arena"; arc.start_match()
	check(not (arc.start_msg["rules"] as Dictionary).has("dest"), "an app-only offline mode (construction): no rules.dest")

	# ---- the host world and a guest world built from its `start` ----
	var hworld := _world(host, host.start_msg)
	await process_frame
	check(host.host_match() != null, "host match is up")
	var start: Dictionary = {}
	for m: Dictionary in host.out:
		if m.get("t") == "start": start = m
	check(not start.is_empty() and (start["rules"] as Dictionary).get("dest") == true, "the `start` carries rules.dest")
	var hd: Destruct = hworld.sim.destruct
	check(hd != null and hd.total() > 0 and not hd.remote, "host world has authoritative breakables (%d)" % (hd.total() if hd else 0))
	var guest := FakeGuest.new()
	guest.slot = 1
	guest.phase = GuestSession.Phase.MATCH
	var gworld := _world(guest, start.duplicate(true))
	await process_frame
	var gd: Destruct = gworld.sim.destruct
	check(gd != null and gd.remote, "guest world has remote breakables")
	check(gd != null and hd != null and _ids(gd) == _ids(hd), "host and guest picked the SAME breakables (%d)" % (gd.total() if gd else 0))
	check(gworld.sim.rubble == null and hworld.sim.rubble == null, "no offline rubble in an online room")

	# ---- a host break reaches the guest and shows debris ----
	var mark := host.out.size()
	var i0 := 0
	hd.break_hit(i0, 99999.0, [1.0, 0.0, 0.0])
	hworld.present(0.0)
	var brk: Dictionary = {}
	for k in range(mark, host.out.size()):
		if host.out[k].get("t") == "brk": brk = host.out[k]
	check(not brk.is_empty() and int(brk["i"]) == i0, "host break goes out as `brk` (i=%d)" % i0)
	check(_deliver(host, mark, gworld) == 1, "the guest handles one brk")
	check(bool(gd.props[i0]["broken"]), "guest: the component is broken")
	check(gd.solids.find(gd.props[i0]["solid"]) < 0, "guest: its solid left the collision")
	check(not (gd.props[i0]["mesh"] as Node3D).visible, "guest: its mesh is hidden")
	gworld.present(0.0)
	check(gworld._debris != null and gworld._debris.piece_count() > 0, "guest: the break shatters into debris (%d)" % (gworld._debris.piece_count() if gworld._debris else 0))
	check(gd.broken_indices() == hd.broken_indices(), "no divergence after one break")
	var again := _deliver(host, mark, gworld)         # the same brk twice (a duplicate) changes nothing
	check(gd.broken_count() == 1 and again == 1, "a repeated brk is harmless")

	# ---- guests never decide ----
	var gout := (guest.out as Array).size()
	var j := 1 if hd.total() > 1 else 0
	var gj := gd.break_hit(j, 99999.0, [0.0, 0.0, 1.0])
	gworld.present(0.0)
	check(not gj and not bool(gd.props[j]["broken"]), "guest: a local hit never breaks a component (hp is the host's)")
	check(float(gd.props[j]["hp"]) == float(gd.props[j]["max_hp"]), "guest: hp is never rolled")
	var sent_brk := false
	for k in range(gout, guest.out.size()):
		if guest.out[k].get("t") in ["brk", "brs"]: sent_brk = true
	check(not sent_brk, "guest never sends brk / brs")
	hworld.net_match.handle({"t": "brk", "i": j, "d": []})
	hworld.present(0.0)
	check(not bool(hd.props[j]["broken"]), "a forged brk at the host is ignored")
	check(not host.GUEST_MSGS.has("brk") and not host.GUEST_MSGS.has("brs"), "the host guard does not relay guest brk / brs")

	# ---- respawn is host-authored ----
	mark = host.out.size()
	hd.step(100000.0)
	hworld.present(0.0)
	var brs := 0
	for k in range(mark, host.out.size()):
		if host.out[k].get("t") == "brs" and int(host.out[k]["i"]) == i0: brs += 1
	check(brs == 1, "respawn goes out as `brs`")
	_deliver(host, mark, gworld)
	check(not bool(gd.props[i0]["broken"]) and gd.solids.find(gd.props[i0]["solid"]) >= 0, "guest: the component is back with its collision")
	check(gd.broken_indices() == hd.broken_indices(), "no divergence after the respawn")

	# ---- a late joiner and a host migration ----
	hd.break_hit(0, 99999.0, [1.0, 0.0, 0.0])
	if hd.total() > 2: hd.break_hit(2, 99999.0, [0.0, 0.0, 1.0])
	hworld.present(0.0)
	var broken := hd.broken_indices()
	var joiner_start: Dictionary = host.start_msg_for(host.host_match())
	check(joiner_start.get("brks", []) == broken and (joiner_start["rules"] as Dictionary).get("dest") == true, "a joiner's start carries brks %s" % [broken])
	var late := FakeGuest.new()
	late.slot = 2; late.phase = GuestSession.Phase.MATCH
	var lworld := _world(late, joiner_start.duplicate(true))
	await process_frame
	check(lworld.sim.destruct.broken_indices() == broken, "late joiner: the broken components are already gone")
	lworld.present(0.0)
	check(lworld._debris == null or lworld._debris.piece_count() == 0, "late joiner: no debris for old breaks")
	for i in broken: check(lworld.sim.destruct.solids.find(lworld.sim.destruct.props[i]["solid"]) < 0, "late joiner: component %d has no collision" % i)
	_deliver(host, 0, gworld)                         # the guest that was there all along hears the same breaks
	check(gd.broken_indices() == broken, "the running guest agrees with the late joiner")
	var rsx: Dictionary = gworld.net_match.capture_resume().get("rsx", {})
	check(rsx.get("brks", []) == broken, "a guest's migration state carries rsx.brks")
	var mig := _host(false); mig.start_match()
	var mstart := (mig.start_msg as Dictionary).duplicate(true)
	mstart["rs"] = []; mstart["rsx"] = rsx
	mstart["rules"] = (start["rules"] as Dictionary).duplicate(true)
	var mworld := _world(mig, mstart)
	await process_frame
	check(mworld.sim.destruct != null and mworld.sim.destruct.broken_indices() == broken and not mworld.sim.destruct.remote, "migrated host resumes the broken list")
	check(mworld.sim.destruct.pending_count() == broken.size(), "migrated host runs the respawn timers from now")

	# ---- a web guest cannot join or stay ----
	host.direct.clear()
	host._hello(77, {"proto": NetClient.PROTO, "name": "Web", "skin": "none", "hat": "none", "color": 0x39b5a8, "cls": "wobbler"})
	var kicked := false
	for e: Array in host.direct:
		if (e[1] as Dictionary).get("t") == "kick": kicked = true
	check(kicked and not host.cid_slot.has(77), "a web guest is refused by a room with breakable cover")
	check(host.web_guests().is_empty(), "the web guest did not enter the roster")

	for w: Node in [hworld, gworld, lworld, mworld]: w.queue_free()
	await process_frame
	print("NETDESTRUCT %s checks=%d fails=%d" % ["ok" if fails == 0 else "FAILED", checks, fails])
	quit(0 if fails == 0 else 1)
