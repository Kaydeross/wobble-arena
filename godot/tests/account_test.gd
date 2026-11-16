extends SceneTree
## Accounts + cloud save against the real server (run by tools/test-godot-account.js, which starts server.js with a
## temp DATA_DIR and makes a web-shaped account first):
##   godot --headless --path godot --script res://tests/account_test.gd -- --no-save --api=http://127.0.0.1:PORT --web=USER:PASS
## Device A = the Save autoload and its Save.cloud (login state in Settings); device B = a second SaveProfile with its own
## AccountApi (login state in memory). Checks: offline login and offline pushes never block (sync line "Saved on this
## device", retry planned); sign up (recovery code XXXX-XXXX-XXXX-XXXX, the device profile becomes the cloud save);
## debounced push after a change; a fresh device takes the cloud silently; a push from a device that is behind gets
## `stale` -> conflict -> Use cloud / Keep this device; a guest profile signing in gets the conflict choice; change
## password; forgot password with the recovery code; pick a name (claim: no password) then protect it and log in elsewhere; the web account's blob (web keys kept) loads and syncs back;
## the server wallet on the signed-in path: the seed, grants, a purchase, a queued offline grant replayed with the same
## idempotency id, and a cloud save whose coin count tries to raise the balance (the server balance wins);
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

## A wallet reply from the real server (the same endpoint the client uses), for checks the UI does not show.
func _wallet(api: Node) -> Dictionary:
	var out := {"r": {}}
	api.call_api(HTTPClient.METHOD_GET, "/api/wallet", null, str(api.getv("token")), func(r: Dictionary) -> void: out["r"] = r)
	await _until(func() -> bool: return not (out["r"] as Dictionary).is_empty())
	return out["r"]

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
	a.setv("wallet_user", "offline_me"); a.wallet_ready = true; a.wallet_coins = 500
	save.add_coins(1)
	check(a.dirty and a._push_in > 0.0, "a change while signed in plans a push")
	check(a._wallet_ops().size() == 1, "an offline signed-in award is queued for the wallet")
	check(await _until(func() -> bool: return a.offline and not a.busy), "the push fails offline")
	check(a.sync_text().begins_with("Saved on this device"), "offline note: %s" % a.sync_text())
	check(a.dirty and a._push_in > 0.0, "and is retried later")
	check(Time.get_ticks_msec() - t0 < 15000, "offline handling is quick")
	a._clear_login()
	save.reset()
	a.base_override = base

	# --- sign up: recovery code, the device profile is the first cloud save, the wallet seeds from it
	save.add_coins(10)
	a.signup(name, mail, "first-pass1")
	r = await _done(a)
	check(r[1], "sign up: %s" % r[2])
	check(a.signed_in() and a.user() == name and a.email() == mail, "signed in as %s" % a.user())
	check(codes.size() == 1 and _is_code(codes[0]), "recovery code shown once (%s)" % [codes])
	check(a.t > 0 and not a.dirty, "first cloud save made with the account (t=%d)" % a.t)
	check(a.sync_text().begins_with("Saved to cloud"), "sync line: %s" % a.sync_text())
	check(await _until(func() -> bool: return a.wallet_ready, 10.0), "the wallet answered after sign-in")
	check(a.wallet_coins == 510 and save.coins == 510, "the first wallet use seeded 510 coins from the cloud save (%d / %d)" % [a.wallet_coins, save.coins])
	var wseed := await _wallet(a)
	check(wseed.ok and wseed.coins == 510 and wseed.ledger[-1]["reason"] == "migrate", "the seed is recorded as a migrate ledger entry")
	check(a._wallet_ops().is_empty(), "the previous account's offline queue was dropped on sign-in")
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
	check(await _until(func() -> bool: return a._wallet_ops().is_empty() and a.wallet_coins == 560, 10.0), "the award went through the wallet (server %d)" % a.wallet_coins)
	check(save.coins == 560, "the shown balance follows the server (%d)" % save.coins)
	var wgrant := await _wallet(a)
	check(wgrant.coins == 560 and wgrant.ledger[-1]["reason"] == "earn", "the award is in the server ledger")

	# --- device B: a fresh profile takes the cloud without asking
	var bp: Node = SaveProfile.new()
	bp.persist = false
	var b := AccountApi.new()
	b.use_settings = false; b.base_override = base; b.profile = bp; b.push_delay = 0.3; b.retry_delay = 0.5
	bp.cloud = b                                        # a second "device": its profile earns through its own wallet
	root.add_child(b)
	var bconf: Array = []
	b.conflict.connect(func(i: Dictionary) -> void: bconf.append(i))
	b.login(mail, "first-pass1")                       # by email
	r = await _done(b)
	check(r[1] and bconf.is_empty(), "device B logs in by email, no question (%s)" % r[2])
	check(await _until(func() -> bool: return b.wallet_ready and bp.coins == 560, 10.0), "device B takes the server wallet balance (%d / %d)" % [bp.coins, save.coins])

	# --- B saves, then A (behind) saves: stale -> conflict -> Use cloud. Coins alone no longer conflict (the wallet
	# owns them); stats and owned items still do.
	bp.add_coins(7)
	check(await _until(func() -> bool: return not b.dirty and not b.busy and b._wallet_ops().is_empty(), 10.0), "device B pushed")
	bp.stats["matches"] = int(bp.stats["matches"]) + 1
	bp.commit()
	check(await _until(func() -> bool: return not b.dirty and not b.busy, 10.0), "device B pushed a stat change")
	save.add_coins(3)
	check(await _until(func() -> bool: return a.stale, 10.0), "device A gets stale")
	check(conflicts.size() == 1 and str(conflicts[0]).contains("coins"), "conflict summaries %s" % [conflicts])
	check(a.sync_text().contains("another device"), "sync line says so: %s" % a.sync_text())
	save.stats["hits"] = int(save.stats["hits"]) + 1
	save.commit()
	check(a._push_in < 0.0 and not a.busy, "nothing is pushed while the question waits")
	a.use_cloud()
	check(save.coins == 570 and int(save.stats["matches"]) == 1 and not a.stale and not a.dirty, "Use cloud: cloud progress, server balance (%d)" % save.coins)

	# --- again, Keep this device: A's progress overwrites the cloud, B picks it up at its next check
	await create_timer(0.9).timeout
	bp.add_coins(100)
	check(await _until(func() -> bool: return not b.dirty and not b.busy and b._wallet_ops().is_empty(), 10.0), "device B pushed again")
	bp.stats["kos"] = int(bp.stats["kos"]) + 1
	bp.commit()
	check(await _until(func() -> bool: return not b.dirty and not b.busy, 10.0), "device B saved its stat")
	save.stats["kos"] = int(save.stats["kos"]) + 2
	save.commit()
	check(await _until(func() -> bool: return a.stale, 10.0), "device A stale again")
	a.keep_device()
	check(await _until(func() -> bool: return not a.dirty and not a.busy and not a.stale and save.coins == 670, 10.0), "Keep this device pushed")
	check(save.coins == 670, "Keep this device still shows the server balance (%d)" % save.coins)
	b.verify()
	check(await _until(func() -> bool: return int(bp.stats["kos"]) == int(save.stats["kos"]) and bp.coins == 670, 10.0), "device B takes the newer cloud + wallet (%d coins, %d kos)" % [bp.coins, int(bp.stats["kos"])])

	# --- a guest profile signing in: the choice is offered when real progress (not just coins) differs
	a.logout()
	r = await _done(a)
	check(r[1] and not a.signed_in(), "log out: %s" % r[2])
	save.add_coins(5)
	save.stats["kos"] = int(save.stats["kos"]) + 3
	save.commit()
	check(not a.dirty, "guests have nothing to push")
	conflicts.clear()
	a.login(name, "first-pass1")
	r = await _done(a)
	check(r[1] and conflicts.size() == 1 and a.stale, "different progress on sign-in asks (%s)" % [conflicts])
	a.keep_device()
	check(await _until(func() -> bool: return not a.dirty and not a.busy, 10.0), "kept this device")
	check(save.coins == 670 and int(save.stats["kos"]) == int(bp.stats["kos"]) + 3, "the guest stats kept, coins back to the server balance (%d)" % save.coins)

	# --- wallet spend: the server price table charges the shipped price and the shown balance follows it
	var bal_spend := a.wallet_coins
	var price_dab := LockerData.emote_price("dab")
	check(save.buy("emote", "dab") == "ok", "a signed-in purchase is accepted locally")
	check(save.owned.has("dab"), "the item is granted at once")
	check(await _until(func() -> bool: return a._wallet_ops().is_empty() and a.wallet_coins == bal_spend - price_dab, 10.0), "the purchase went through the wallet (%d -> %d)" % [bal_spend, a.wallet_coins])
	check(save.coins == bal_spend - price_dab, "the shown balance follows the server (%d)" % save.coins)
	var wbuy := await _wallet(a)
	check(wbuy.coins == a.wallet_coins and wbuy.ledger[-1]["reason"] == "spend" and wbuy.ledger[-1]["amount"] == -price_dab, "the spend is in the server ledger")

	# --- offline earning: queued, replayed with the same idempotency id, never doubled
	a.base_override = "http://127.0.0.1:9"
	var bal_off := a.wallet_coins
	save.add_coins(40)
	check(save.coins == bal_off + 40 and a._wallet_ops().size() == 1, "an offline award is shown locally and queued")
	var op: Dictionary = a._wallet_ops()[0]
	a.base_override = base
	a.offline = false
	a.wallet_fetch()
	check(await _until(func() -> bool: return a._wallet_ops().is_empty() and a.wallet_coins == bal_off + 40, 10.0), "back online: the queued award replayed (%d)" % a.wallet_coins)
	var replay := {"r": {}}
	a.call_api(HTTPClient.METHOD_POST, "/api/wallet/grant", {"id": op["id"], "reason": op["reason"], "amount": int(op["amount"]), "kos": op.get("kos", 0), "won": op.get("won", false)}, str(a.getv("token")),
		func(r: Dictionary) -> void: replay["r"] = r)
	await _until(func() -> bool: return not (replay["r"] as Dictionary).is_empty())
	var rr: Dictionary = replay["r"]
	check(rr.get("ok", false) and rr.get("replay", false) and int(rr.get("coins", -1)) == bal_off + 40, "replaying the same id changes nothing")
	check(save.coins == bal_off + 40, "the balance is unchanged by the replay (%d)" % save.coins)

	# --- the cloud save can not raise coins: a blob with 999999 coins is pulled, the server balance wins
	check(await _until(func() -> bool: return not a.dirty and not a.busy, 10.0), "the wallet change was pushed before the merge check")
	await create_timer(0.9).timeout                       # the server allows one save per 800 ms
	var rich: Dictionary = save.get_blob().duplicate(true)
	rich["wallet"]["coins"] = 999999
	rich["stats"]["matches"] = int(rich["stats"]["matches"]) + 10
	var put := {"r": {}}
	a.call_api(HTTPClient.METHOD_PUT, "/api/save", {"data": rich, "base": a.t, "force": true}, str(a.getv("token")), func(r: Dictionary) -> void: put["r"] = r)
	await _until(func() -> bool: return not (put["r"] as Dictionary).is_empty())
	var pr: Dictionary = put["r"]
	check(pr.get("ok", false), "a cloud save with a huge coin count was accepted (the blob stays client data): %s" % [pr])
	var bal_before := a.wallet_coins
	a.verify()
	check(await _until(func() -> bool: return a.t == int(pr.get("t", 0)) and int(save.stats["matches"]) == int(rich["stats"]["matches"]), 10.0), "the cloud save was pulled")
	check(save.coins == bal_before and save.coins != 999999, "the merge cannot raise coins: server balance wins (%d)" % save.coins)

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

	# --- pick a name: no password, no email, no recovery code; then protect it and use it on a second device
	a.logout()
	await _done(a)
	var pick := "pick_%d" % (randi() % 100000)
	var ncodes := codes.size()
	a.claim("a!")
	r = await _done(a)
	check(not r[1] and not a.signed_in(), "a bad name is refused: %s" % r[2])
	a.claim(pick)
	r = await _done(a)
	check(r[1] and a.signed_in() and a.user() == pick and a.email() == "", "claim: signed in as %s with just a name (%s)" % [a.user(), r[2]])
	check(not a.has_password and codes.size() == ncodes, "a name-only account: no password, no recovery code")
	check(a.t > 0 and not a.dirty, "its first cloud save was made")
	bad.claim(pick.to_upper())
	r = await _done(bad)
	check(not r[1] and str(r[2]).contains("taken"), "the name is taken, whatever the case: %s" % r[2])
	b.login(pick, "nothing1")
	r = await _done(b)
	check(not r[1], "a name-only account can't log in on another device")
	a.protect("short")
	r = await _done(a)
	check(not r[1] and not a.has_password, "a too-short password is refused: %s" % r[2])
	a.protect("pick-pass1")
	r = await _done(a)
	check(r[1] and a.has_password and codes.size() == ncodes + 1 and _is_code(codes[-1]), "protect: password set and a recovery code shown (%s)" % r[2])
	b.login(pick, "pick-pass1")
	r = await _done(b)
	check(r[1] and b.user() == pick and b.has_password, "the protected name logs in on device B")
	a.delete_account("pick-pass1")
	r = await _done(a)
	check(r[1], "cleanup: the picked name is deleted")

	# --- the web account: its blob loads here (web-only keys kept) and syncs back
	a.logout()
	await _done(a)
	conflicts.clear()
	a.login(web_user, web_pass)
	r = await _done(a)
	check(r[1], "web account login: %s" % r[2])
	if conflicts.size() == 1: a.use_cloud()
	check(await _until(func() -> bool: return a.wallet_ready and save.coins == 2222, 10.0), "the wallet seeded 2222 from the web save (%d)" % save.coins)
	check(save.look["hat"] == "crown" and save.look["cls"] == "kid" and save.owned.has("dab"), "web progress loaded (%s)" % [save.look])
	check(save.get_blob().get("cfg") is Dictionary and save.get_blob()["cfg"].get("mode") == "ffa", "web settings kept in the blob")
	check(str(root.get_node("Settings").get_value("hat")) == "crown", "the look reaches Settings")
	save.add_coins(100)
	check(await _until(func() -> bool: return not a.dirty and not a.busy and a._wallet_ops().is_empty() and a.wallet_coins == 2322, 10.0), "web account pushed and earned through the wallet")
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
