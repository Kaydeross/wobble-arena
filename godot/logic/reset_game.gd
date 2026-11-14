class_name ResetGame
extends RefCounted
## "Reset game" (Settings > About): this device goes back to a new install. The owner's switch for a deliberate
## "start from scratch" (the account keeps developer-wide unlocks, so this is not an accident switch).
##
## One wipe:
##   1. the account session is signed out locally (AccountApi._clear_login: token / user / email / cloud_* keys, the
##      pending push and any cloud conflict);
##   2. the profile is back to a fresh one (Save.wipe(): 500 coins, the free outfits, Wobble Dance, zeroed stats,
##      fresh goals and a locked Construction DLC);
##   3. every preference is back to DEFAULTS (Settings.wipe_all(): the file is removed, so the next run starts fresh;
##      language, volumes, Kids mode, touch layout, server address, ads / store-cache keys included);
##   4. the in-memory caches derived from those preferences are cleared too (store entitlement cache, ad consent,
##      blocked names, the remote launch config goes back to its bundled defaults) so this session behaves like a new
##      install before the scene reloads. RemoteConfig keeps nothing on disk; it re-fetches on the next launch;
##   5. the profile files in user:// are removed (only the exact known names, never other files or folders);
##   6. the title scene is reloaded (the project's existing restart path, scripts/main.gd) so everything rebuilds.
##
## Testable and safe: under `--no-save` (every tools/test-*.js run) `persist` is false and no file is deleted — exactly
## like Settings.persist / Save.persist, so a test can never destroy the developer's real save. Tests replace `files`
## with throwaway user:// names and `reload_hook` with a recorder instead of a real scene change (tests/reset_test.gd).
##   docs/RESET.md

const SCENE := "res://scenes/main.tscn"
## The profile files in user:// a wipe removes. `settings.cfg` belongs to Settings.wipe_all() above; the Construction
## DLC and the account login state live inside profile.json / settings.cfg, so there is no second save file.
static var files: Array = ["profile.json", "profile.json.bak", "profile.json.tmp"]
## false on `--no-save` runs (tests): the wipe resets memory but never deletes a file on disk.
static var persist := not OS.get_cmdline_user_args().has("--no-save")
## Tests set this to a Callable to record the reload instead of changing the scene (the wipe returns reloaded = true).
static var reload_hook: Callable = Callable()

## Wipes everything and reloads the title. Returns a short summary for tests / logging:
## {settings, profile, signed_out, files, reloaded}.
static func wipe_all() -> Dictionary:
	var out := {"settings": false, "profile": false, "signed_out": false, "files": 0, "reloaded": false}
	var sv := _node("Save")
	var st := _node("Settings")
	# 1-3 first: the account / store caches write their keys through Settings, whose wipe comes after them.
	var cloud: Node = sv.get("cloud") if sv != null else null
	if cloud != null and cloud.has_method("_clear_login"):
		cloud.call("_clear_login")
		cloud.set("expired", false)   # a new install's login has not "run out": no stale note on the Account sheet
		out["signed_out"] = not bool(cloud.call("signed_in"))
	var ent := _node("Entitlements")
	if ent != null and ent.has_method("revoke"):
		for id: String in ent.KNOWN:
			if bool(ent.call("has", id)): ent.call("revoke", id)
	var ads := _node("Ads")
	if ads != null and ads.has_method("set_consent"): ads.call("set_consent", "unknown")
	var rc := _node("RemoteConfig")
	if rc != null and rc.get("values") is Dictionary:   # a new install starts on the bundled launch config
		var bundled: Dictionary = rc.get("DEFAULTS")
		rc.set("values", bundled.duplicate(true))
		rc.set("source", "bundled")
		rc.set("last_error", "")
	if sv != null and sv.has_method("wipe"):
		sv.call("wipe")
		out["profile"] = true
	if st != null and st.has_method("wipe_all"):
		st.call("wipe_all")
		out["settings"] = true
	var safety := _node("Safety")
	if safety != null and safety.has_method("_load"): safety.call("_load")   # the blocked names came from the wiped setting
	# 4-5: the profile files, only when this is a real run (never under --no-save) and only the known names.
	if persist: out["files"] = purge(files)
	# 6: the title scene, which rebuilds everything from the reset autoloads.
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and _reload(tree): out["reloaded"] = true
	return out

## Removes only files in the user:// root whose exact name is in `known`; folders and every other file stay. Returns
## how many were removed. Static and explicit so a test can point it at throwaway names.
static func purge(known: Array) -> int:
	var dir := DirAccess.open("user://")
	if dir == null: return 0
	var found: Array = []
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and known.has(entry): found.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	var removed := 0
	for name: String in found:
		if DirAccess.remove_absolute(ProjectSettings.globalize_path("user://" + name)) == OK: removed += 1
	return removed

## The title scene again (the "Quit to title" path, scripts/main.gd). A test's reload_hook replaces the real reload.
static func _reload(tree: SceneTree) -> bool:
	if reload_hook.is_valid():
		reload_hook.call()
		return true
	return tree.change_scene_to_file(SCENE) == OK

static func _node(n: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null: return null
	return tree.root.get_node_or_null(n)
