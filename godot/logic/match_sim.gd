class_name MatchSim
extends RefCounted
## One offline match, pure logic (no nodes): the fighters, their controllers (PlayerControl / BotBrain), Combat,
## crates, and the fixed-step update in the web game's simStep order (public/index.html ~9630):
##   simTime -> input + bots (melee ticks inside) -> per fighter timers + physics -> bounce pads -> crates ->
##   projectiles -> ring-out -> separate -> animate tick (yaw, crouch, recoil climb).
## The melee sweep runs once per rendered frame after the animation wrote the hand/arm points: call sweep().
## Match setup follows loadMap (~7598) and setBotCfg (~7333).

const BOT_CLASS_ORDER := ["bruiser", "kid", "alien", "elder", "wobbler"]   ## index.html ~4812
const BOT_COLORS := [0xf08a3c, 0xd9534f, 0x8e6bd8, 0x4a90d9, 0xe0b030, 0x5fb760, 0xe86fa5, 0x7a8793, 0x2fb5c7, 0xb5651d, 0x9acd32, 0xff7f7f]
const BOT_POOL := ["Bot Wibble", "Bot Bonk", "Bot Gus", "Bot Pip", "Bot Moxie", "Bot Dozer", "Bot Noodle", "Bot Jelly", "Bot Fizz",
	"Bot Barney", "Bot Tubs", "Bot Wob", "Bot Splat", "Bot Boing", "Bot Zonk", "Bot Biscuit", "Bot Waffle", "Bot Squish", "Bot Mango",
	"Bot Pickles", "Bot Doink", "Bot Muffin", "Bot Sprocket", "Bot Nugget", "Bot Tater", "Bot Blorp", "Bot Wumpus", "Bot Pogo",
	"Bot Crumb", "Bot Zigzag"]
const RING_OUT_Y := -25.0

var combat := Combat.new()
var pickups: Pickups
var map_id := ""
var map: Dictionary = {}
var solids: Array = []
var pads: Array = []
var ladders: Array = []
var fighters: Array = []          ## = combat.fighters
var player: FighterState
var controllers := {}             ## FighterState -> PlayerControl / BotBrain
var looks := {}                   ## FighterState -> {skin, hat, color}
var diff := "normal"
var difficulty: Dictionary = {}
var match_start := 0.0
## Online: the NetMatch (net/net_match.gd) of this match, or null offline. step() calls its pre_step() before the
## controllers (netSnap) and post_controls() after them (netStep), like simStep.
var net: RefCounted = null
## Dynamic arenas (logic/arena_dyn.gd). Set dyn_choice / dyn_seed / dyn_t0 before setup(); online they come from
## start.rules (dyn, dseed, dt0) so every client moves the same tiles at the same match time.
var dyn := ArenaDyn.new()
var dyn_choice := "off"
var dyn_seed := 0
var dyn_t0 := 0.0

func _init(content_dir: String = "res://data") -> void:
	combat.load_content(content_dir)
	pickups = Pickups.new(combat, Combat.read_json(content_dir.path_join("drops.json")), Combat.read_json(content_dir.path_join("crate-rates.json")))

## The game mode (pickMode + setBotCfg): rules, teams, lives, K.O. limit (`limit` < 0 = the mode's preset). Call before
## setup(); pass ModeRules.bot_count(mode_id, ...) as setup's bot_count. See logic/mode_rules.gd.
func configure(mode_id: String, limit: int = -1) -> void:
	combat.rules.configure(mode_id, limit)

## Break the reference cycles (fighters <-> combat, controllers) when the match ends.
func dispose() -> void:
	for b in controllers.values():
		if b is BotBrain: b.target = null
	controllers.clear()
	looks.clear()
	pickups.list.clear()
	combat.dispose()
	fighters = []
	player = null

## loadMap + setBotCfg: the player (class from the caller, usually Settings) and `bot_count` bots in the JS class order.
func setup(p_map_id: String, p_map: Dictionary, map_ladders: Array, map_pads: Array, player_class: String, player_control: PlayerControl,
		bot_count: int = 3, p_diff: String = "normal") -> void:
	map_id = p_map_id
	map = p_map
	solids = FighterPhysics.solids_from_map(map)
	ladders = map_ladders
	pads = map_pads
	diff = p_diff
	difficulty = (Combat.read_json("res://data/difficulties.json") as Dictionary).get(diff, {})
	dyn.setup(map_id, map, solids, ladders, pads, dyn_choice, dyn_seed)   # dynSetup: may split the floor into tiles in `solids`
	combat.solids = solids
	combat.spawns = map.get("spawns", [])
	combat.spawn_y = float(map["spawnY"]) if map.has("spawnY") else 4.0
	combat.fighters = []
	fighters = combat.fighters
	pickups.set_map(map)
	match_start = combat.time

	player = _new_fighter(player_class, true)
	player.name = "You"
	controllers[player] = player_control
	var pp: Array = map.get("player", [0, 0])
	combat.place_at(player, float(pp[0]), float(pp[1]), float(pp[2]) if pp.size() > 2 else 0.01)
	player.yaw = PI; player.face_yaw = PI

	# bots start in a different spot every match: bot spots + spawns, not next to the player, shuffled
	var pool: Array = []
	var seen := {}
	for sp: Array in map.get("bots", []) + map.get("spawns", []):
		var key := "%s,%s" % [sp[0], sp[1]]
		if seen.has(key) or Vector2(float(sp[0]) - float(pp[0]), float(sp[1]) - float(pp[1])).length() < 5.0: continue
		seen[key] = true
		pool.append(sp)
	for k in range(pool.size() - 1, 0, -1):
		var j := int(floor(combat.rng.next() * (k + 1)))
		var t: Variant = pool[k]; pool[k] = pool[j]; pool[j] = t
	var names := BOT_POOL.duplicate()
	for k in range(names.size() - 1, 0, -1):
		var j := int(floor(combat.rng.next() * (k + 1)))
		var t: Variant = names[k]; names[k] = names[j]; names[j] = t
	var hats: Array = []
	for h: String in (Combat.read_json("res://data/cosmetics.json") as Dictionary).get("hats", []):
		if h != "none" and h != "crown": hats.append(h)
	for i in bot_count:
		var b := _new_fighter(BOT_CLASS_ORDER[i % BOT_CLASS_ORDER.size()], false)
		b.name = names[i % names.size()]
		b.dmg_scale = float(difficulty.get("dmg", 0.45))
		b.phys.speed = float(difficulty.get("speed", 4.4))
		looks[b] = {"skin": "none", "hat": hats[i % hats.size()] if hats.size() > 0 else "none", "color": BOT_COLORS[i % BOT_COLORS.size()]}
		var brain := BotBrain.new(difficulty, diff)
		brain.ai_t = combat.rng.range_f(0.5, 3); b.kick_cool = combat.rng.range_f(1, 4)
		controllers[b] = brain
		var x := 0.0
		var z := 0.0
		var y := 0.01
		if i < pool.size():
			var sp: Array = pool[i]
			x = float(sp[0]); z = float(sp[1]); y = float(sp[2]) if sp.size() > 2 else float(map.get("spawnY", 0.01))
		else:                             # extra bots: a spot on a ring around the middle
			var ang := combat.rng.range_f(0, 6.283)
			var rr := combat.rng.range_f(0.35, 0.8) * float(map.get("wander", 10))
			x = cos(ang) * rr; z = sin(ang) * rr
		combat.place_at(b, x, z, y)
		b.yaw = combat.rng.range_f(0, PI * 2.0); b.face_yaw = b.yaw
	var bots: Array = fighters.slice(1)
	combat.rules.start_match(player, bots)         # teams, lives, dash charges, Weapon Ladder
	for b: FighterState in bots:
		var tc := combat.rules.team_color(b)
		if tc >= 0: looks[b]["color"] = tc
		if combat.mode_id == "ninja": looks[b]["skin"] = "shadow"     # dressBots
	combat.rules.setup_shrink(map_id, map, solids)

## One more (non-player) fighter, e.g. an online ghost: class stats, map, full health. The caller places it.
func add_fighter(cid: String) -> FighterState:
	return _new_fighter(cid, false)

func _new_fighter(cid: String, is_player: bool) -> FighterState:
	var f := FighterState.new()
	f.id = fighters.size()
	f.is_player = is_player
	f.set_class(cid, combat.classes.get(cid, {}))
	f.phys.set_map(map, ladders)
	f.phys.can_climb = is_player
	f.hp = combat.max_hp(f)
	fighters.append(f)
	return f

## One fixed simulation step (simStep).
func step(dt: float) -> void:
	combat.time += dt
	combat.rules.update(dt, pickups)        # updatePotato / updatePillars / updateShrink (+ the end-of-match countdown)
	dyn.update(dyn_clock(), fighters)       # updateDyn
	var net_pre: Variant = net.call("pre_step") if net != null else null
	for f: FighterState in fighters:
		var c: Variant = controllers.get(f)
		if c != null: c.think(f, self, dt)
	if net != null: net.call("post_controls", dt, net_pre)
	for f: FighterState in fighters:
		combat.timers(f, dt)
		if not f.is_ghost: f.phys.step(dt, solids, f)
	for f: FighterState in fighters:          # updatePads
		var pi := f.phys.bounce_pads(pads, f)
		if pi >= 0:
			combat.kick_lean(f, -2.0, combat.rng.range_f(-1, 1)); combat.kick_head(f, -3.0, combat.rng.range_f(-2, 2))
			combat.ev({"type": "pad", "f": f, "pad": pi})
	pickups.update(dt)
	combat.weapons.step_projectiles(dt)
	_ring_out()
	separate()
	for f: FighterState in fighters:          # the gameplay half of Fighter.animate
		f.yaw += wrapf(f.face_yaw - f.yaw, -PI, PI) * minf(1.0, 12.0 * dt)
		var c: Variant = controllers.get(f)
		var squat: bool = c != null and c.squat
		var want := 1.0 if ((squat or f.trap_t > 0.0) and not f.dead and f.down_t <= 0.0) else 0.0
		f.phys.crouch_k += (want - f.phys.crouch_k) * minf(1.0, dt * 14.0)
		combat.weapons.climb_tick(f, dt)

## meleeSweep for everyone (once per rendered frame, after the hand/arm points were written).
func sweep() -> void:
	for f: FighterState in fighters:
		combat.melee_sweep(f)

## Ring-out: knocked off the edge (simStep ~9640). The kill cam is not ported: the player respawns at once.
func _ring_out() -> void:
	for d: FighterState in fighters:
		if d.phys.py >= RING_OUT_Y or d.elim or d.is_ghost or d.dead: continue
		var a := d.last_attacker
		var knocked := a != null and a != d and combat.time - d.last_hit_time < 10.0
		d.st["streak"] = 0; d.st["multi"] = 0; d.st["deaths"] += 1; d.st["falls"] += 1
		if knocked: combat.add_ko(a, d)
		else: combat.ev({"type": "ko", "killer": null, "victim": d, "weapon": "", "fall": true})
		if combat.net_started and d.net_slot >= 0 and (d.is_player or combat.net_host):     # tell the others about the fall too
			combat.ev({"type": "net", "msg": NetSnapshot.encode_ko(a.net_slot if knocked and a.net_slot >= 0 else -1, d.net_slot)})
		d.last_attacker = null
		var last_life := combat.lives_mode != 0 and d.lives <= 1
		if not last_life and not d.is_player and d.home == null:      # bots don't pop straight back
			d.dead = true; d.fell_t = true; d.death_t = Combat.BOT_RESPAWN
			d.phys.vx = 0.0; d.phys.vy = 0.0; d.phys.vz = 0.0
			combat.clear_inventory(d); combat.set_weapon(d, "")
		else:
			combat.respawn(d)

## separate(): push overlapping fighters apart.
func separate() -> void:
	var r2 := FighterPhysics.R * 2.0
	for i in fighters.size():
		for j in range(i + 1, fighters.size()):
			var a: FighterPhysics = fighters[i].phys
			var b: FighterPhysics = fighters[j].phys
			if fighters[i].dead or fighters[j].dead or absf(a.py - b.py) > 1.5: continue
			var dx := b.px - a.px
			var dz := b.pz - a.pz
			var d := sqrt(dx * dx + dz * dz)
			if d < r2 and d > 0.0001:
				var push := (r2 - d) * 0.5
				a.px -= dx / d * push; a.pz -= dz / d * push
				b.px += dx / d * push; b.pz += dz / d * push

## Fighter.quickMelee: one spatula swing, then back to the held weapon.
func quick_melee(f: FighterState, yaw: float) -> bool:
	if f.dead or f.down_t > 0.0 or f.melee_cool > 0.0 or f.swing >= 0.0:
		return false
	var keep_cool := f.cool
	if f.slot >= 0:
		f.return_slot = f.slot; f.slot = -1
	combat.set_weapon(f, "spatula")
	combat.melee_begin(f, "spatula", yaw)
	f.cool = keep_cool
	f.melee_cool = float(combat.wdata("spatula")["cooldown"])
	return true

## hasLOS: nothing solid between the shoulder and the target's chest.
func has_los(b: FighterState, tg: FighterState) -> bool:
	var dx := tg.chest_x - b.shoulder_x
	var dy := tg.chest_y - b.shoulder_y
	var dz := tg.chest_z - b.shoulder_z
	var d := sqrt(dx * dx + dy * dy + dz * dz)
	if d < 0.1: return true
	var t := combat.weapons.ray_walls(b.shoulder_x, b.shoulder_y, b.shoulder_z, dx / d, dy / d, dz / d, d)
	return t < 0.0

## The dynamic arena clock (dynClock): match time plus the host's offset.
func dyn_clock() -> float:
	return combat.time - match_start + dyn_t0

## MAPS[map].wander (a getter on shrinking maps: bots roam inside the floor that is left).
func wander() -> float:
	var w := combat.rules.shrink_wander()
	return w if not is_nan(w) else float(map.get("wander", 10))

## Match clock in seconds.
func elapsed() -> float:
	return combat.time - match_start
