class_name ModeRules
extends RefCounted
## Game-mode rules ported 1:1 from the web game (public/index.html): match end (addKo limit, endMatch), lives and
## elimination (`eliminate`), teams (setBotCfg team split, TEAM_COL, teamKo), the Weapon Ladder (`GG`, ggGive,
## ggAdvance, initLadder), ninja dashes (doDash, dashTick, DASH_*) and shrinking arenas (MAPS.shrink/squeeze build(),
## updateShrink, the shrink spot in respawn). Pure logic: Combat owns one (`combat.rules`) and calls it from add_ko,
## respawn, place_at and timers; MatchSim calls update() every step. Visuals react to events in combat.events:
##   {"type": "match_over", "winner", "won", "title", "sub"}   endMatch (the match keeps running END_TIME seconds)
##   {"type": "match_finished", "winner", "won"}              the END_TIME ran out: show the results
##   {"type": "eliminated", "f"}                               out of lives
##   {"type": "puff", "kind": "dash", x, y, z}                 a dash
##   {"type": "toast", "text"}                                 player messages (ladder rung, arena growing...)
## Not ported: Hot Potato (no mode in the web MODES table sets `potato` any more: dead code there), Pillars (needs the
## pillar-hopping bot AI and pillarGive), Explosive / Moon Drift (their weapons are not ported yet).

const TEAM_COL := [0x3b82f6, 0xef4444]                  ## TEAM_COL
const GG := ["smg", "ak", "uzi", "shotgun", "revolver", "sniper", "bow", "shuriken", "knife", "glauncher", "bat", "spatula"]   ## the Weapon Ladder
const DASH_MAX := 3
const DASH_REGEN := 4.0
const DASH_CD := 0.45
const DASH_GEAR := ["katana", "shuriken", "knife", "typhoon"]
const END_TIME := 3.4                                   ## endT: the game keeps running for a moment after the last K.O.
const MODE_DEFAULTS := {"count": 3, "hp": 200, "behav": "brawl", "ffa": true, "limit": 0}   ## MODE_DEFAULTS (pickMode)
## Modes the Godot port can play offline (the picker lists these). Explosive needs rockets, Pillars its bot AI, Sandbox and
## Construction belong to other tracks.
const PLAYABLE := ["classic", "melee", "guns", "ninja", "duel", "t2", "t3", "t4", "mega", "giant", "gungame"]
## MODES[k].maps (index.html ~3093; not in shared/modes.json). [] = every level.
const TEAM_MAPS := ["arena", "park", "ice", "temple", "rooftops"]
const MODE_MAPS := {"melee": ["arena", "park", "ice", "rooftops", "cloud", "tower", "brawlpit"], "guns": ["arena", "temple", "rooftops", "gunrange"],
	"ninja": ["temple", "cloud", "rooftops", "tower"], "sandbox": ["custom"], "construction": ["siteyard"], "mega": ["shrink", "squeeze"],
	"pillars": ["pillars", "pillars2"], "duel": TEAM_MAPS, "t2": TEAM_MAPS, "t3": TEAM_MAPS, "t4": TEAM_MAPS}
## The shrinking floors (MAPS.shrink / MAPS.squeeze build(): `shrink = {...}`); the floor is the map's first box.
const SHRINK := {
	"shrink": {"S0": 64.0, "min": 16.0, "max": 40.0, "both": true, "D": 64.0, "rate": 55.0},
	"squeeze": {"S0": 80.0, "min": 22.0, "max": 58.0, "both": false, "D": 36.0, "rate": 34.0},
}

var _combat: WeakRef                 ## weak: Combat owns this object
var combat: Combat:
	get: return _combat.get_ref()
var limit := 0                       ## cfg.limit: K.O.s (team K.O.s in team modes) to win, 0 = no limit
var match_over := false              ## matchOver
var winner: FighterState = null      ## endWinner
var end_t := 0.0                     ## endT
## updateShrink state (empty = this map does not shrink): S0, size, start, min, max, dir, cycle, hold, both, D, rate,
## rest (-1 = unset), box (the floor solid in combat.solids).
var shrink := {}

func _init(c: Combat) -> void:
	_combat = weakref(c)

## The K.O. limit a mode starts with (MODE_DEFAULTS + preset).
static func preset_limit(mode_id: String, modes: Dictionary) -> int:
	return int(modes.get(mode_id, {}).get("preset", {}).get("limit", MODE_DEFAULTS["limit"]))

## How many bots a mode plays with (setBotCfg): teams force teams * 2 - 1, otherwise `requested` (0..12).
static func bot_count(mode_id: String, modes: Dictionary, requested: int) -> int:
	var t := int(modes.get(mode_id, {}).get("teams", 0))
	if t: return t * 2 - 1
	return clampi(requested, 0, 12)

static func maps_for(mode_id: String) -> Array:
	return MODE_MAPS.get(mode_id, [])

## cfg from setBotCfg for `mode_id`: teams, lives, ffa/brawl, giant, hp, K.O. limit (`p_limit` < 0 = the preset's).
func configure(mode_id: String, p_limit: int = -1) -> void:
	var c := combat
	c.set_mode(mode_id)
	var m: Dictionary = c.mode
	var pre: Dictionary = m.get("preset", {})
	c.teams = int(m.get("teams", 0))
	c.lives_mode = int(m.get("lives", 0))
	c.ffa = bool(pre.get("ffa", MODE_DEFAULTS["ffa"]))
	c.brawl = str(pre.get("behav", MODE_DEFAULTS["behav"])) == "brawl"
	if c.teams: c.brawl = true; c.ffa = true
	c.giant = mode_id == "giant"
	if mode_id == "explosive": c.hp_setting = 300.0           # Explosive is always 300 health
	limit = p_limit if p_limit >= 0 else preset_limit(mode_id, c.modes)
	match_over = false; winner = null; end_t = 0.0

## setBotCfg team split + loadMap's per-fighter reset (dashes, lives) + initLadder. `bots` in setup order.
func start_match(player: FighterState, bots: Array) -> void:
	var c := combat
	player.team = 0
	for i in bots.size():
		var b: FighterState = bots[i]
		b.team = (0 if i < c.teams - 1 else 1) if c.teams else -1
	for f: FighterState in [player] + bots:
		f.dash_n = DASH_MAX; f.dash_regen = 0.0; f.dash_cd = 0.0; f.lives = c.lives_mode; f.elim = false
	for f: FighterState in [player] + bots:                     # initLadder
		f.gg_rung = 0
		if c.mode_id == "gungame" and not f.is_ghost: gg_give(f)

func team_color(f: FighterState) -> int:
	return TEAM_COL[f.team] if combat.teams and f.team >= 0 and f.team < TEAM_COL.size() else -1

## teamKo
func team_ko(t: int) -> int:
	var n := 0
	for f: FighterState in combat.fighters:
		if f.team == t: n += f.ko
	return n

# ============================== match end ==============================

## The tail of addKo: the K.O. limit (team K.O.s in team modes).
func check_limit(killer: FighterState) -> void:
	if limit and (team_ko(killer.team) if combat.teams else killer.ko) >= limit and not match_over:
		end_match(killer)

## Did the local player (or their team) win?
func player_won(w: FighterState) -> bool:
	if w == null: return false
	if combat.teams:
		for f: FighterState in combat.fighters:
			if f.is_player: return w.team == f.team
		return false
	return w.is_player

## endMatch (the gameplay half: stats, coins and the menu are the UI's).
func end_match(w: FighterState) -> void:
	match_over = true; winner = w; end_t = END_TIME
	var won := player_won(w)
	var title := ""
	if combat.teams: title = "YOUR TEAM WINS!" if won else "ENEMY TEAM WINS!"
	else: title = "YOU WIN!" if w.is_player else "%s WINS!" % w.name.to_upper()
	var sub := "Last one standing" if combat.lives_mode else ("Finished the Weapon Ladder" if combat.mode.get("ladder", false) else
		"First %sto %d K.O.s" % ["team " if combat.teams else "", limit])
	combat.ev({"type": "match_over", "winner": w, "won": won, "title": title, "sub": sub})

## eliminate: out of lives. `counted` = the death was already counted (respawn after a K.O. / fall).
func eliminate(f: FighterState, counted: bool) -> void:
	var c := combat
	if f.elim: return
	f.elim = true; f.lives = 0
	if not f.dead:
		if not counted: f.st["deaths"] += 1
		f.st["streak"] = 0; f.st["multi"] = 0; f.dead = true; f.fall_side = -1 if c.rng.next() < 0.5 else 1; f.down_t = 0.0; f.kick_t = -1.0
		c.clear_inventory(f); c.set_weapon(f, "")
	f.death_t = 1e9
	c.ev({"type": "eliminated", "f": f})
	var alive: Array = []
	for x: FighterState in c.fighters:
		if not x.elim and not x.left: alive.append(x)
	var online := c.net_started
	if f.is_player and (c.mode_id == "pillars" or online) and not match_over: c.ev({"type": "toast", "text": "You're out! Spectating."})
	if not match_over and c.lives_mode and (alive.size() <= 1 or (f.is_player and c.mode_id != "pillars" and not online)):
		var best: FighterState = null                          # alive.sort((a, b) => b.lives - a.lives || b.ko - a.ko)[0] (stable)
		for x: FighterState in alive:
			if best == null or x.lives > best.lives or (x.lives == best.lives and x.ko > best.ko): best = x
		end_match(best if best != null else f)

# ============================== Weapon Ladder ==============================

## ggGive: the weapon of the fighter's current rung, nothing else.
func gg_give(f: FighterState) -> void:
	var k: String = GG[mini(GG.size() - 1, f.gg_rung)]
	combat.clear_inventory(f); combat.set_weapon(f, "spatula")
	if k != "spatula": combat.pickup(f, k)

## ggAdvance: a K.O. moves the killer one rung up; past the last rung wins.
func gg_advance(killer: FighterState) -> void:
	if killer == null or match_over: return
	killer.gg_rung += 1
	if killer.gg_rung >= GG.size():
		killer.gg_rung = GG.size() - 1; end_match(killer); return
	if killer.is_ghost: return                  # an online player's own machine swaps their weapon
	if not killer.dead:
		gg_give(killer); killer.invuln = maxf(killer.invuln, 1.0)
	if killer.is_player:
		combat.ev({"type": "toast", "text": "Weapon %d of %d: %s" % [killer.gg_rung + 1, GG.size(), combat.wdata(GG[killer.gg_rung]).get("name", "Spatula")]})

# ============================== ninja dash ==============================

## dashGear: only while holding a ninja weapon (anything in Pillars).
func dash_gear(f: FighterState) -> bool:
	return combat.mode_id == "pillars" or (f.slot >= 0 and DASH_GEAR.has(f.weapon))

## doDash: a burst of speed toward (ix, iz) (the facing when there is no input). 3 charges.
func do_dash(f: FighterState, ix: float, iz: float) -> bool:
	if not dash_gear(f) or f.dead or f.down_t > 0.0 or f.trap_t > 0.0 or f.dash_n <= 0 or f.dash_cd > 0.0: return false
	var l := sqrt(ix * ix + iz * iz)
	if l < 0.05:
		ix = sin(f.yaw); iz = cos(f.yaw); l = 1.0
	var p := f.phys
	p.vx = ix / l * 24.0; p.vz = iz / l * 24.0
	if p.grounded: p.vy = maxf(p.vy, 1.2)
	if combat.mode_id == "pillars": f.dash_air_t = 0.45
	f.dash_n -= 1; f.dash_cd = DASH_CD
	if f.dash_n == DASH_MAX - 1: f.dash_regen = 0.0
	combat.ev({"type": "puff", "kind": "dash", "x": p.px, "y": p.py + 0.9, "z": p.pz, "dx": ix / l, "dz": iz / l})
	combat.ev({"type": "sfx", "name": "swing", "f": f})
	return true

## dashTick (first thing in Fighter.timers).
func dash_tick(f: FighterState, dt: float) -> void:
	f.dash_cd = maxf(0.0, f.dash_cd - dt)
	if f.dash_n < DASH_MAX:
		f.dash_regen += dt
		if f.dash_regen >= DASH_REGEN:
			f.dash_regen = 0.0; f.dash_n += 1
	else: f.dash_regen = 0.0

# ============================== shrinking arenas ==============================

## The shrink state for maps that shrink (MAPS[id].shrinks; build() makes the floor box solids[0]).
func setup_shrink(map_id: String, map: Dictionary, solids: Array) -> void:
	shrink = {}
	if not map.get("shrinks", false) or not SHRINK.has(map_id) or solids.is_empty(): return
	var d: Dictionary = SHRINK[map_id]
	shrink = {"S0": d["S0"], "size": d["S0"], "start": d["S0"], "min": d["min"], "max": d["max"], "dir": -1, "cycle": 0, "hold": 5.0,
		"both": d["both"], "D": d["D"], "rate": d["rate"], "rest": -1.0, "box": solids[0], "id": map_id}

## updateShrink (match time; stops at match end).
func update_shrink(dt: float, pickups: Pickups = null) -> void:
	var s := shrink
	if s.is_empty() or match_over: return
	if s["hold"] > 0.0:
		s["hold"] -= dt; return
	if s["dir"] == 1:
		s["size"] = minf(s["max"], s["size"] + 1.8 * dt)
		if s["size"] >= s["max"]: s["dir"] = -1; s["start"] = s["max"]; s["hold"] = 3.0
	elif s["size"] > s["min"]:
		s["size"] = maxf(s["min"], s["size"] - (s["start"] - s["min"]) / s["rate"] * dt)
	elif _all_down():                       # everyone fell: bring the arena back at half the original size
		s["cycle"] += 1; s["start"] = maxf(14.0, float(Combat.js_round(s["S0"] * 0.5))); s["size"] = s["start"]; s["hold"] = 4.0
		combat.ev({"type": "toast", "text": "Arena reset at half size!"})
	else:                                   # at its smallest: a short breather, then it starts growing again
		s["rest"] = (5.0 if s["rest"] < 0.0 else s["rest"]) - dt
		if s["rest"] <= 0.0:
			s["rest"] = -1.0; s["dir"] = 1
			combat.ev({"type": "toast", "text": "The arena is growing!"})
	var hd: float = s["size"] / 2.0 if s["both"] else s["D"] / 2.0
	var b: Dictionary = s["box"]
	b["minX"] = -s["size"] / 2.0; b["maxX"] = s["size"] / 2.0; b["minZ"] = -hd; b["maxZ"] = hd
	if pickups != null:                     # crates on the collapsed edge go with it
		for i in range(pickups.list.size() - 1, -1, -1):
			var q: Dictionary = pickups.list[i]
			if absf(q["x"]) > s["size"] / 2.0 or absf(q["z"]) > hd:
				pickups.list.remove_at(i)
				combat.ev({"type": "crate_gone", "crate": q})
		pickups.spots = shrink_drops()

func _all_down() -> bool:
	for f: FighterState in combat.fighters:
		if not (f.dead or f.elim or f.phys.py < -2.0): return false
	return true

## respawn's spot inside the shrink zone ([] = not shrinking). Consumes the same random numbers as the JS.
func shrink_spot() -> Array:
	var s := shrink
	if s.is_empty(): return []
	var rng := combat.rng
	if s["both"]:
		var rr := rng.next() * maxf(0.0, s["size"] / 2.0 - 2.5)
		var an := rng.next() * 6.283
		return [cos(an) * rr, sin(an) * rr]
	var hx := maxf(0.0, s["size"] / 2.0 - 2.5)
	var hz2: float = s["D"] / 2.0 - 2.5
	var x := (rng.next() * 2.0 - 1.0) * hx
	var z := (rng.next() * 2.0 - 1.0) * hz2
	return [x, z]

## MAPS.shrink/squeeze `wander` getter (bots roam inside the live floor); NAN = not shrinking.
func shrink_wander() -> float:
	if shrink.is_empty(): return NAN
	return maxf(3.0, shrink["size"] / 2.0 - 3.0)

## MAPS.shrink/squeeze `drops` getter.
func shrink_drops() -> Array:
	var r := maxf(2.0, shrink["size"] / 2.0 - 3.0)
	if shrink["id"] == "squeeze":
		return [[r * 0.6, 4], [-r * 0.6, -4], [r * 0.9, -7], [-r * 0.9, 7], [r * 0.3, 8], [-r * 0.3, -8]]
	return [[r * 0.5, 0], [-r * 0.5, 0], [0, r * 0.5], [0, -r * 0.5], [r * 0.8, r * 0.6], [-r * 0.8, -r * 0.6]]

# ============================== per step ==============================

## simStep's mode updates (updatePotato / updatePillars / updateShrink) plus the end-of-match countdown.
func update(dt: float, pickups: Pickups = null) -> void:
	update_shrink(dt, pickups)
	if end_t > 0.0:
		end_t -= dt
		if end_t <= 0.0:
			end_t = 0.0
			combat.ev({"type": "match_finished", "winner": winner, "won": player_won(winner)})

## The mode line under the K.O. counter (updateModeHud + updateKoText), "" = nothing to show.
func hud_text(player: FighterState) -> String:
	var c := combat
	if player == null: return ""
	var t := ""
	if c.lives_mode and c.mode_id != "pillars":
		t = "♥".repeat(player.lives) if player.lives > 0 else "OUT"
	elif c.teams:
		var mine := player.team
		t = "Team %d v %d" % [team_ko(mine), team_ko(1 - mine)] + (" / %d" % limit if limit else "")
	elif limit:
		t = "%d / %d K.O.s" % [player.ko, limit]
	var extra := ""
	if c.mode_id == "gungame" and not match_over:
		extra = "Weapon %d of %d · %s" % [player.gg_rung + 1, GG.size(), c.wdata(GG[player.gg_rung]).get("name", "Spatula")]
	elif not shrink.is_empty() and not match_over:
		var s := shrink
		extra = "Arena %dm" % Combat.js_round(s["size"]) + (" · shrinking soon" if s["hold"] > 0.0 else (" · growing" if s["dir"] == 1 else (" · smallest" if s["size"] <= s["min"] else "")))
	if dash_gear(player) and not player.dead:
		extra += ("   " if extra != "" else "") + "Dash " + "◆".repeat(player.dash_n) + "◇".repeat(DASH_MAX - player.dash_n)
	return t if extra == "" else (t + "   " + extra if t != "" else extra)
