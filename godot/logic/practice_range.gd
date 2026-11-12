class_name PracticeRange
extends RefCounted
## The range maps (MAPS.practice / MAPS.test, `range` in maps.json) ported from the web game:
##   - loadMap: a range map always plays with range.count dummies (cfg.behav 'dummy', class Wobbler, speed 2.2,
##     damage x0.45) standing on the map's bot spots in order, each with a `home` (MatchSim.setup does this);
##   - rangeBot (index.html ~7764): a dummy never attacks; it faces the player and either stands still or slides along
##     its mover path (range.movers[index]: centre cx/cz, amplitude ax/az, rate w, phase ph, speed);
##   - Combat: a K.O.'d dummy pops back up at its home after 1.2 s with 0.3 s of spawn protection (Fighter.hit/respawn);
##   - the weapon racks: placeSideRacks (Practice Range) and placeWeaponGrid (Test Map: every weapon), laid out on the
##     floor as crates that come back 2.5 s after they are taken (Pickups.place_perm, permQ).
## Parity: tools/test-range.js runs the real rangeBot against range_bot() (npm run test:godot-range).

const RACK_LEFT := ["ak", "smg", "minigun", "sniper", "shotgun", "uzi"]                ## MAPS.practice build(): placeSideRacks
const RACK_RIGHT := ["revolver", "flame", "bow", "knife", "shuriken", "boomerang"]
const RACK_W := 30.0
## WCATS (index.html ~8614) in order: the Test Map lays out every weapon that drops (DROP_BASE and WEAPONS).
const WCATS_ORDER := ["uzi", "ak", "smg", "minigun", "revolver", "mammoth", "shotgun", "sniper", "flame", "rocket", "glauncher",
	"cluster", "meteor", "snow", "net", "bat", "mallet", "trident", "glove", "knife", "shuriken", "boomerang", "bow", "snake",
	"blower", "katana", "typhoon", "hammer", "wirewhip", "heal", "speed", "rage", "shield"]
const DUMMY_SPEED := 2.2
const DUMMY_DMG := 0.45

static func is_range(map: Dictionary) -> bool:
	return map.get("range") is Dictionary

static func dummy_count(map: Dictionary) -> int:
	return int((map["range"] as Dictionary).get("count", 0)) if is_range(map) else 0

## The rack for a range map: [[key, x, z], ...] in the web's spawn order.
static func rack(map_id: String, combat: Combat, drop_base: Dictionary) -> Array:
	var out: Array = []
	if map_id == "practice":                                      # placeSideRacks(left, right, -W + 5, W - 5, 18, 3)
		for i in RACK_LEFT.size(): out.append([RACK_LEFT[i], -RACK_W + 5.0, 18.0 - i * 3.0])
		for i in RACK_RIGHT.size(): out.append([RACK_RIGHT[i], RACK_W - 5.0, 18.0 - i * 3.0])
	elif map_id == "test":                                        # placeWeaponGrid(keys, 0, 4, 10, 3)
		var keys: Array = []
		for k: String in WCATS_ORDER:
			if drop_base.has(k) and not combat.wdata(k).is_empty(): keys.append(k)
		var cols := 10
		for i in keys.size():
			var r := i / cols
			var c := i % cols
			var n := mini(cols, keys.size() - r * cols)
			out.append([keys[i], 0.0 + (c - (n - 1) / 2.0) * 3.0, 4.0 + r * 3.0])
	return out

## Lays the rack out (loadMap -> m.build()).
static func place_rack(map_id: String, pickups: Pickups) -> void:
	for e: Array in rack(map_id, pickups.combat, pickups.drops.get("base", {})):
		pickups.place_perm(e[0], e[1], e[2])

## rangeBot: one dummy, one step. `idx` = its index among the bots (bots.indexOf(b)), `mover` = range.movers[idx]
## ({} = it stands still), `brain` keeps the mover clock (b.mt). Writes phys.wish_x/z, phys.speed, face_yaw.
static func range_bot(b: FighterState, idx: int, player: FighterState, rcfg: Dictionary, dt: float, brain: BotBrain) -> void:
	var p := b.phys
	var mv: Dictionary = (rcfg.get("movers", {}) as Dictionary).get(str(idx), {})
	p.wish_x = 0.0; p.wish_z = 0.0; b.swing = -1.0; brain.target = null; p.want_jump = false
	if b.dead or b.down_t > 0.0: return
	if player != null: b.face_yaw = atan2(player.phys.px - p.px, player.phys.pz - p.pz)
	if not mv.is_empty():
		brain.mt += dt
		var ph := float(mv["w"]) * brain.mt + float(mv.get("ph", 0.0))
		var ex := float(mv["cx"]) + float(mv["ax"]) * sin(ph) - p.px
		var ez := float(mv["cz"]) + float(mv["az"]) * sin(ph) - p.pz
		var d := sqrt(ex * ex + ez * ez)
		p.speed = float(mv["speed"]) if float(mv.get("speed", 0.0)) != 0.0 else 4.0
		if d > 0.25:
			p.wish_x = ex / d; p.wish_z = ez / d
