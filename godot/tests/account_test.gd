extends SceneTree
## Accounts + cloud save against the real server (run by tools/test-godot-account.js, which starts server.js with a
## temp DATA_DIR and makes a web-shaped account first):
##   godot --headless --path godot --script res://tests/account_test.gd -- --no-save --api=http://127.0.0.1:PORT --web=USER:PASS
## Device A = the Save autoload and its Save.cloud (login state in Settings); device B = a second SaveProfile with its own
## AccountApi (login state in memory). Checks: offline login and offline pushes never block (sync line "Saved on this
## device", retry planned); sign up (recovery code XXXX-XXXX-XXXX-XXXX, the device profile becomes the cloud save);
## debounced push after a change; a fresh device takes the cloud silently; a push from a device that is behind gets
## `stale` -> conflict -> Use cloud / Keep this device; a guest profile signing in gets the conflict choice; change
## password; forgot password with the recovery code; the web account's blob (web keys kept) loads and syncs back;
## delete account; an expired token signs out and keeps the profile.
## Prints WEB_COINS=<n> for the Node side to check on the server.

var fails := 0
var base := ""
var web_user := ""
var web_pass := ""
var codes: Array = []

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok: fails += 1

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--api="): base = a.substr(6)
		elif a.begins_with("--web="):
			var p := a.substr(6).split(":")
			web_user = p[0]; web_pass = p[1]
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _until(cond: Callable, secs := 8.0) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		if Time.get_ticks_msec() - t0 > secs * 1000.0: return false
		await process_frame
	return true

func _done(api: Node) -> Array:
	return await api.done

func _run() -> void:
	var save: Node = root.get_node("Save")
	var a: AccountApi = save.cloud
	a.push_delay = 0.3
	a.retry_delay = 0.5
	a.recovery.connect(func(c: String) -> void: codes.append(c))
	var conflicts: Array = []
	a.conflict.connect(func(i: Dictionary) -> void: conflicts.append(i))
	var name := "gd_%d" % (randi() % 100000)
	var mail := name + "@example.com"

	# --- offline: nothing blocks, the profile stays on the device
	a.base_override = "http://127.0.0.1:9"
	var t0 := Time.get_ticks_msec()
	a.login("anyone", "secret1")
	var r := await _done(a)
	check(not r[1] and str(r[2]).contains("reach"), "offline login fails with a plain message (%s)" % r[2])
	check(not a.signed_in(), "still a guest")
	a.setv("token", "ab".repeat(32)); a.setv("user", "offline_me")
	save.add_coins(1)
	check(a.dirty and a._push_in > 0.0, "a change while signed in plans a push")
	check(await _until(func() -> bool: return a.offline and not a.busy), "the push fails offline")
	check(a.sync_text().begins_with("Saved on this device"), "offline note: %s" % a.sync_text())
	check(a.dirty and a._push_in > 0.0, "and is retried later")
	check(Time.get_ticks_msec() - t0 < 15000, "offline handling is quick")
	a._clear_login()
	save.reset()
	a.base_override = base

	# --- sign up: recovery code, the device profile is the first cloud save
	save.add_coins(10)
	a.signup(name, mail, "first-pass1")
	r = await _done(a)
	check(r[1], "sign up: %s" % r[2])
	check(a.signed_in() and a.user() == name and a.email() == mail, "signed in as %s" % a.user())
	check(codes.size() == 1 and _is_code(codes[0]), "recovery code shown once (%s)" % [codes])
	check(a.t > 0 and not a.dirty, "first cloud save made with the account (t=%d)" % a.t)
	check(a.sync_text().begins_with("Saved to cloud"), "sync line: %s" % a.sync_text())
	var bad := AccountApi.new()
	bad.use_settings = false; bad.base_override = base; bad.profile = SaveProfile.new()
	root.add_child(bad)
	bad.signup(name, "x" + mail, "whatever1")
	r = await _done(bad)
	check(not r[1] and str(r[2]).contains("taken"), "a taken username is refused: %s" % r[2])

	# --- a change is pushed after the debounce
	var t1 := a.t
	save.add_coins(50)
	check(a.dirty, "change marks the cloud save dirty")
	check(await _until(func() -> bool: return not a.dirty and a.t > t1), "debounced push sent (t %d -> %d)" % [t1, a.t])

	# --- device B: a fresh profile takes the cloud without asking
	var bp: Node = SaveProfile.new()
	bp.persist = false
	var b := AccountApi.new()
	b.use_settings = false; b.base_override = base; b.profile = bp; b.push_delay = 0.3; b.retry_delay = 0.5
	root.add_child(b)
	var bconf: Array = []
	b.conflict.connect(func(i: Dictionary) -> void: bconf.append(i))
	b.login(mail, "first-pass1")                       # by email
	r = await _done(b)
	check(r[1] and bconf.is_empty(), "device B logs in by email, no question (%s)" % r[2])
	check(bp.coins == save.coins and bp.coins == 560, "device B has the cloud progress (%d / %d)" % [bp.coins, save.coins])

	# --- B saves, then A (behind) saves: stale -> conflict -> Use cloud
	bp.add_coins(7)
	check(await _until(func() -> bool: return not b.dirty and not b.busy, 10.0), "device B pushed")
	save.add_coins(3)
	check(await _until(func() -> bool: return a.stale, 10.0), "device A gets stale")
	check(conflicts.size() == 1 and str(conflicts[0]["cloud"]).begins_with("567 coins") and str(conflicts[0]["local"]).begins_with("563 coins"), "conflict summaries %s" % [conflicts])
	check(a.sync_text().contains("another device"), "sync line says so: %s" % a.sync_text())
	save.add_coins(1)
	check(a._push_in < 0.0 and not a.busy, "nothing is pushed while the question waits")
	a.use_cloud()
	check(save.coins == 567 and not a.stale and not a.dirty, "Use cloud: the cloud progress here (%d)" % save.coins)

	# --- again, Keep this device: A's progress overwrites the cloud, B picks it up at its next check
	await create_timer(0.9).timeout
	bp.add_coins(100)
	check(await _until(func() -> bool: return not b.dirty and not b.busy, 10.0), "device B pushed again")
	save.add_coins(2000)
	check(await _until(func() -> bool: return a.stale, 10.0), "device A stale again")
	a.keep_device()
	check(await _until(func() -> bool: return not a.dirty and not a.busy and not a.stale, 10.0), "Keep this device pushed")
	b.verify()
	check(await _until(func() -> bool: return bp.coins == save.coins, 10.0), "device B takes the newer cloud at start-up (%d)" % bp.coins)

	# --- a guest profile signing in: the choice is offered
	a.logout()
	r = await _done(a)
	check(r[1] and not a.signed_in(), "log out: %s" % r[2])
	save.add_coins(5)
	check(not a.dirty, "guests have nothing to push")
	conflicts.clear()
	a.login(name, "first-pass1")
	r = await _done(a)
	check(r[1] and conflicts.size() == 1 and a.stale, "different progress on sign-in asks (%s)" % [conflicts])
	a.keep_device()
	check(await _until(func() -> bool: return not a.dirty and not a.busy, 10.0), "kept this device")

	# --- change password
	a.change_password("wrong-pass", "second-pass2")
	r = await _done(a)
	check(not r[1] and str(r[2]).contains("wrong"), "wrong current password refused: %s" % r[2])
	a.change_password("first-pass1", "second-pass2")
	r = await _done(a)
	check(r[1], "password changed: %s" % r[2])
	b.login(name, "first-pass1")
	r = await _done(b)
	check(not r[1], "old password no longer works")
	b.login(name, "second-pass2")
	r = await _done(b)
	check(r[1], "new password works")

	# --- forgot the password: the recovery code
	var bcodes: Array = []
	b.recovery.connect(func(c: String) -> void: bcodes.append(c))
	b.reset(name, "AAAA-BBBB-CCCC-DDDD", "third-pass3")
	r = await _done(b)
	check(not r[1], "a wrong recovery code is refused")
	b.reset(name, str(codes[0]).to_lower().replace("-", " "), "third-pass3")
	r = await _done(b)
	check(r[1] and b.signed_in() and bcodes.size() == 1 and _is_code(bcodes[0]) and bcodes[0] != codes[0], "reset with the recovery code signs in + new code (%s)" % r[2])

	# --- the web account: its blob loads here (web-only keys kept) and syncs back
	a.logout()
	await _done(a)
	conflicts.clear()
	a.login(web_user, web_pass)
	r = await _done(a)
	check(r[1], "web account login: %s" % r[2])
	if conflicts.size() == 1: a.use_cloud()
	check(save.coins == 2222 and save.look["hat"] == "crown" and save.look["cls"] == "kid" and save.owned.has("dab"), "web progress loaded (%d coins, %s)" % [save.coins, save.look])
	check(save.get_blob().get("cfg") is Dictionary and save.get_blob()["cfg"].get("mode") == "ffa", "web settings kept in the blob")
	check(str(root.get_node("Settings").get_value("hat")) == "crown", "the look reaches Settings")
	save.add_coins(100)
	check(await _until(func() -> bool: return not a.dirty and not a.busy, 10.0), "web account pushed")
	print("WEB_COINS=%d" % save.coins)

	# --- delete the Godot account
	a.logout()
	await _done(a)
	a.login(name, "third-pass3")
	await _done(a)
	if a.stale: a.use_cloud()
	a.delete_account("nope-nope")
	r = await _done(a)
	check(not r[1] and a.signed_in(), "delete needs the right password: %s" % r[2])
	a.delete_account("third-pass3")
	r = await _done(a)
	check(r[1] and not a.signed_in() and save.coins == 500, "account deleted, a fresh guest here (%s)" % r[2])
	b.login(name, "third-pass3")
	r = await _done(b)
	check(not r[1] and int(r.size()) == 3, "the deleted account cannot log in: %s" % r[2])

	# --- an expired login: signed out, the profile stays
	b.setv("token", "cd".repeat(32)); b.setv("user", "ghost")
	bp.coins = 4321
	b.verify()
	check(await _until(func() -> bool: return b.expired), "expired token -> signed out")
	check(not b.signed_in() and bp.coins == 4321 and b.sync_text().contains("ran out"), "profile kept, plain note: %s" % b.sync_text())

	bad.profile.free(); bad.queue_free(); b.queue_free(); bp.free()
	await create_timer(0.5).timeout                    # (the last fire-and-forget logout call finishes)
	print("ACCOUNT %s" % ("ok" if fails == 0 else "FAILED (%d)" % fails))
	quit(0 if fails == 0 else 1)

static func _is_code(c: String) -> bool:
	var re := RegEx.new()
	re.compile("^[A-Z2-9]{4}-[A-Z2-9]{4}-[A-Z2-9]{4}-[A-Z2-9]{4}$")
	return re.search(c) != null
