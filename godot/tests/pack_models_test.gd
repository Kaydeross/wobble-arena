extends SceneTree
## Pack models and cosmetics (phase B of the Kitchen / Xmas / Australia packs): the 18 pack weapons build bounded, sane models, an unknown
## key still gives the grey placeholder, every pack hat / outfit builds on a Wobbler of every class, and locker.json lists them consistently
## and pack-gated like Construction's.
## godot --headless --path godot --script res://tests/pack_models_test.gd

const MAX_MESHES := 60
const MAX_VERTS := 3000
const MAX_HAT_PARTS := 20
var fails: Array[String] = []


func _check(ok: bool, msg: String) -> void:
	if not ok:
		fails.append(msg)


func _count(n: Node) -> Array:                      # [meshes, vertices]
	var m := 0
	var v := 0
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		m = 1
		var me: Mesh = (n as MeshInstance3D).mesh
		for s in me.get_surface_count():
			v += (me.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	for c in n.get_children():
		var r := _count(c)
		m += r[0]
		v += r[1]
	return [m, v]


func _init() -> void:
	var w: Wobbler = preload("res://actors/wobbler.tscn").instantiate()
	root.add_child(w)
	var st := {"pos": Vector3.ZERO, "vel": Vector3.ZERO, "yaw": 0.0, "grounded": true, "aim": Vector3(0, -0.5, 0.8)}
	var worst := [0, 0]
	_check(WeaponModels.PACK_KEYS.size() == 18, "18 pack weapon ids (%d)" % WeaponModels.PACK_KEYS.size())
	for key: String in WeaponModels.PACK_KEYS:
		_check(not WeaponModels.KEYS.has(key) and not WeaponModels.DLC_KEYS.has(key), "%s clashes with a shared / Construction weapon id" % key)
		var m := WeaponModels.build(key)
		_check(m is Node3D and m.name == "Weapon_" + key, "%s: not a Weapon_ node" % key)
		var c := _count(m)
		var bb := WeaponModels.bounds(m)
		var longest := maxf(bb.size.x, maxf(bb.size.y, bb.size.z))
		_check(c[0] >= 5 and c[0] <= MAX_MESHES, "%s: %d meshes (5..%d)" % [key, c[0], MAX_MESHES])
		_check(c[1] > 0 and c[1] <= MAX_VERTS, "%s: %d vertices (max %d)" % [key, c[1], MAX_VERTS])
		_check(longest >= 0.7 and longest <= 3.4, "%s: longest side %.2f" % [key, longest])
		_check(bb.position.y > -3.2 and bb.end.y < 1.5, "%s: y %.2f..%.2f outside the hand's reach" % [key, bb.position.y, bb.end.y])
		for ch in m.get_children():
			if ch is MeshInstance3D:
				_check((ch as MeshInstance3D).material_override != null, "%s: a mesh has no material" % key)
		var again := WeaponModels.build(key)
		_check(again.get_child_count() == m.get_child_count(), "%s: build is not deterministic" % key)
		again.free()
		m.free()
		w.set_weapon(key)
		for f in 5:
			w.apply_state(st)
			w.animate(1.0 / 60.0)
		_check(w.weapon == key and w._weapon_mi != null and w._weapon_mi.mesh.get_surface_count() > 0, "%s: does not fuse / equip" % key)
		print("PACKMODELS %-18s meshes=%2d verts=%4d longest=%.2f" % [key, c[0], c[1], longest])
		worst = [maxi(worst[0], c[0]), maxi(worst[1], c[1])]
	var u := WeaponModels.build("no_such_weapon")
	_check(u.get_child_count() == 2 and u.name == "Weapon_no_such_weapon", "an unknown key still gives the 2-block placeholder")
	u.free()
	var h := WeaponModels.build("hammer")
	_check(h.get_child_count() == 6, "the shared hammer is unchanged")
	h.free()
	_looks(w, st)
	_locker()
	print("PACKMODELS worst: %d meshes, %d vertices" % [worst[0], worst[1]])
	for f in fails:
		print("FAIL ", f)
	print("PACKMODELS_RESULT fails=%d" % fails.size())
	quit(0 if fails.is_empty() else 1)


func _looks(w: Wobbler, st: Dictionary) -> void:
	var hats := PackLooks.all_hat_ids()
	var skins := PackLooks.all_skin_ids()
	_check(hats.size() == 10 and skins.size() == 4, "10 pack hats and 4 pack outfits (%d, %d)" % [hats.size(), skins.size()])
	for h: String in hats:
		var parts := WobblerLooks.hat_parts(h)
		_check(WobblerLooks.has_hat(h) and parts.size() >= 3 and parts.size() <= MAX_HAT_PARTS, "hat %s has %d parts" % [h, parts.size()])
		_check(not WobblerLooks.HATS.has(h), "hat %s clashes with a core hat" % h)
		_check((WobblerLooks.data("cosmetics")["hats"] as Array).has(h), "hat %s is not in cosmetics hats" % h)
		for pt: Array in parts:
			_check(String(pt[0]) == "hat" and pt[1] is Array and pt[3] is Array, "hat %s has a malformed part" % h)
	for k: String in skins:
		_check(WobblerLooks.skin_def(k).size() > 0 and not WobblerLooks.skin_parts(k).is_empty(), "outfit %s has a skin def and parts" % k)
		_check(WobblerLooks.skin_parts(k).size() <= 80, "outfit %s has %d parts" % [k, WobblerLooks.skin_parts(k).size()])
	_check(WobblerLooks.skin_def("dishiebot").get("noTorso", false) and PackLooks.replaces_head("dishiebot"), "Dishie Bot replaces head and torso")
	var built := 0
	for cls: String in WobblerLooks.data("classes").keys():
		for k: String in skins:
			w.setup(cls, k, "none", WobblerLooks.DEFAULT_COLOR)
			w.apply_state(st)
			w.animate(1.0 / 60.0)
			_check(w.skin_key == k, "%s did not take outfit %s" % [cls, k])
			built += 1
		for h: String in hats:
			w.setup(cls, "none", h, WobblerLooks.DEFAULT_COLOR)
			w.apply_state(st)
			w.animate(1.0 / 60.0)
			_check(w.hat_name == h and w.hat != null, "%s did not take hat %s" % [cls, h])
			built += 1
	w.setup("wobbler", "elftunic", "santabeard", WobblerLooks.DEFAULT_COLOR)       # an outfit with a hat, and back to nothing
	w.apply_state(st)
	w.animate(1.0 / 60.0)
	w.set_hat("none")
	w.set_skin("none")
	_check(w.hat == null and w.skin_key == "none", "hat and outfit clear")
	for core: String in ["santa", "chef", "cowboy", "hardhat", "foreman"]:
		_check(WobblerLooks.HATS.has(core) and WobblerLooks.has_hat(core), "core hat %s untouched" % core)
	print("PACKMODELS looks: %d class x hat/outfit builds" % built)


func _locker() -> void:
	var d := LockerData.data()
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/cosmetics.json"))
	var pi: Dictionary = d.get("pack_items", {})
	_check(pi.keys().size() == 3 and pi.has("kitchen") and pi.has("xmas") and pi.has("australia"), "pack_items has the three packs")
	var hat_ids: Array = []
	var skin_ids: Array = []
	var seen := {}
	for pack: String in pi:
		var it: Dictionary = pi[pack]
		var arc: Dictionary = it.get("arcade_hats", {})
		_check(arc.has("normal") and arc.has("nightmare") and arc["normal"] != arc["nightmare"], "%s has a Normal and a Nightmare victory hat" % pack)
		var ids: Array = (it.get("hats", []) as Array) + arc.values()
		hat_ids.append_array(ids)
		skin_ids.append_array(it.get("skins", []))
		_check(LockerData.RARITIES.find(str(d["hat_rarity"].get(arc.get("normal", ""), ""))) >= LockerData.RARITIES.find("rare"), "%s Normal victory hat is at least rare like Site Foreman" % pack)
		_check(LockerData.RARITIES.find(str(d["hat_rarity"].get(arc.get("nightmare", ""), ""))) >= LockerData.RARITIES.find(str(d["hat_rarity"].get(arc.get("normal", ""), ""))), "%s Nightmare victory hat is at least as rare as Normal" % pack)
	for h: String in hat_ids:
		_check(not seen.has("h" + h), "duplicate hat id %s" % h)
		seen["h" + h] = true
		_check(not (raw["hats"] as Array).has(h), "hat %s clashes with a shared hat" % h)
		_check((d["extra_hats"] as Array).has(h), "hat %s is not in extra_hats" % h)
		_check(d["hat_label"].has(h) and str(d["hat_label"][h]) != "", "hat %s has no label" % h)
		_check(LockerData.RARITIES.has(str(d["hat_rarity"].get(h, ""))), "hat %s has no valid rarity" % h)
		_check(d["pack_tags"].has(h), "hat %s has no tag" % h)
	for k: String in skin_ids:
		_check(not seen.has("s" + k), "duplicate outfit id %s" % k)
		seen["s" + k] = true
		_check(not (raw["skins"] as Dictionary).has(k), "outfit %s clashes with a shared outfit" % k)
		var sk: Dictionary = d["extra_skins"].get(k, {})
		for f in ["name", "icon", "col", "tone", "pants", "shoes"]:
			_check(sk.has(f), "outfit %s lacks %s" % [k, f])
		_check(LockerData.RARITIES.has(str(d["pack_skin_rarity"].get(k, ""))) and LockerData.skin_rarity(k) == d["pack_skin_rarity"][k], "outfit %s has no valid rarity" % k)
		_check(not d["skin_shop"].has(k) and not (d["free_skins"] as Array).has(k) and not d["code_skins"].has(k) and LockerData.skin_price(k) == 0, "outfit %s must not be sold, free or a code outfit" % k)
		_check(d["pack_tags"].has(k), "outfit %s has no tag" % k)
		_check(LockerData.pack_of(k) != "", "outfit %s belongs to no pack" % k)
	_check((d["extra_hats"] as Array).size() == 4 + hat_ids.size(), "extra_hats = the 4 Construction hats + the pack hats")
	_check((d["extra_skins"] as Dictionary).size() == skin_ids.size(), "extra_skins = the pack outfits")
	_check(d["exclusive_hats"] == ["foreman"] and str(d["hat_rarity"]["foreman"]) == "rare", "Construction's exclusive hat is untouched")
	# pack gating (the same idea as Construction's exclusive hat: not listed until owned / won)
	var all: Array = LockerData.cosmetics().get("hats", [])
	for h: String in hat_ids:
		_check(all.has(h), "cosmetics hats lists %s" % h)
	var none := LockerData.hats_for(all, {}, [])
	for h: String in hat_ids:
		_check(not none.has(h), "a profile that owns nothing must not see %s" % h)
	_check(none.has("hardhat") and none.has("crown") and none.has("foreman"), "core and Construction hats are not gated here")
	var dlc := {"packs": {"kitchen": {"owned": true, "arcade_clears": {"normal": ["_victory"], "nightmare": []}}}}
	var own := LockerData.hats_for(all, dlc, [])
	_check(own.has("toque") and own.has("toque_gold") and not own.has("toque_inferno"), "a kitchen owner sees the toque and the Normal hat only after winning Normal")
	_check(not own.has("santabeard") and not own.has("slouch") and not own.has("santa_gold"), "a kitchen owner sees no Xmas / Australia items")
	var devs := LockerData.hats_for(all, {}, ["dev"])
	_check(devs.has("santabeard") and devs.has("elfcap") and devs.has("slouch") and not devs.has("slouch_gold"), "the developer code owns every pack, but the victory hats still need winning")
	var gone := LockerData.hats()
	for h: String in hat_ids:
		_check(not gone.has(h), "LockerData.hats() hides %s on a fresh profile" % h)
	var fake := RefCounted.new()
	fake.set_script(load("res://tests/pack_models_fake_save.gd"))
	LockerData.grant_pack_skins(fake, "xmas")
	LockerData.grant_pack_skins(fake, "xmas")
	_check(fake.get("skins") == ["none", "elftunic"], "grant_pack_skins adds the outfits once (%s)" % [fake.get("skins")])
	print("PACKMODELS locker: %d hats, %d outfits, gating ok" % [hat_ids.size(), skin_ids.size()])
