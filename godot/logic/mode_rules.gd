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
##   {"type": "chaos_warn", "id", "name", "in"}              Chaos: an event is about to fire (banner + countdown)
##   {"type": "chaos", "id", "name", "dur"} / {"type": "chaos_end", "id"}   Chaos: an event started / ended
## Godot-only modes (res://data/extra/modes.json, merged by merge_extra): Team Deathmatch (tdm: two teams sized by the
## Players page, team limit 30), Death Match (deathmatch: free for all to 20), Sudden Death (sudden: one life, a K.O. or
## a fall eliminates, the player spectates until one fighter stands), Chaos (chaos: 5 v 5 to 50 with random events).
## Pillars (initPillars, pillarGive, updatePillars): 8 fighters on the eight pillars (PillarsMap), one life, any weapon
## dashes, a random weapon into everyone's inventory every 10 s (first at 1.2 s), last one standing or the most K.O.s
## (fewest deaths on a tie) when the 3-minute clock runs out. Explosive: launchers only, always 300 health. Moon Drift
## (lowg): its preset gravity 0.15 goes to Combat.grav_setting and every fighter's FighterPhysics.grav_scale (projG and
## the gentler jump follow from it). Practice Range (practice, the web PRACTICE button): the range maps' dummies
## (PracticeRange), no score.
## Sandbox (sandbox, offline only like the web game): build your own arena on 'custom' (SandboxLayout, ui/build_hud.gd),
## then Play runs a free for all with bots on it, first to SANDBOX_LIMIT K.O.s. Pillars plays on Pillars or Lava
## Pillars (pillars2, PillarsMap.lava_entry: the same rules, a lava lake that ends you).
## Not ported: Hot Potato (no mode in the web MODES table sets `potato` any more: dead code there).

const TEAM_COL := [0x3b82f6, 0xef4444]                  ## TEAM_COL
const GG := ["smg", "ak", "uzi", "shotgun", "revolver", "sniper", "bow", "shuriken", "knife", "glauncher", "bat", "spatula"]   ## the Weapon Ladder
const DASH_MAX := 3
const DASH_REGEN := 4.0
const DASH_CD := 0.45
const DASH_GEAR := ["katana", "shuriken", "knife", "typhoon"]
const END_TIME := 3.4                                   ## endT: the game keeps running for a moment after the last K.O.
const MODE_DEFAULTS := {"count": 3, "hp": 200, "behav": "brawl", "ffa": true, "limit": 0}   ## MODE_DEFAULTS (pickMode)
## Modes the Godot port can play offline (the picker lists these). Sandbox and Construction belong to other tracks.
const PLAYABLE := ["classic", "melee", "guns", "ninja", "duel", "t2", "t3", "t4", "mega", "giant", "gungame",
	"tdm", "deathmatch", "sudden", "chaos", "pillars", "explosive", "lowg", "practice", "sandbox"]
## Offline only (the web netMode sends Sandbox and Construction matches online as Classic).
const OFFLINE_ONLY := ["sandbox", "construction"]
const SANDBOX_LIMIT := 10            ## a test run on your arena ends at this many K.O.s (the web Sandbox has no limit)
## Short card text for the wizard (the web menu's BLURB, index.html ~3743), where the mode's `desc` is too long.
const BLURB := {"pillars": "Start on pillars. A new weapon every 10 seconds. One life",
	"explosive": "Explosives only. Always 300 health", "lowg": "Super low gravity. Float, soar and knock rivals around",
	"practice": "Dummies to shoot and a rack of weapons. No score",
	"sandbox": "Build your own arena with blocks, then play it with bots"}
## Pillars (MODES.pillars, PIL_BAN, pillarGive): the weapons pillarGive hands out, in DROP_POOL order, with their WT
## weight (common 8, uncommon 6, rare 4, epic 2.5, legendary 2 by RARITY) = unique DROP_POOL minus PIL_BAN, heal and
## the power-ups (shared/modes.json cannot carry it: the web `allow` reads PIL_BAN, which the export does not see).
## tools/modes-reference.js runs the real pillarGive, so a change on the web side fails the parity test.
const PIL_POOL := [["shuriken", 6.0], ["bow", 4.0], ["knife", 6.0], ["ak", 6.0], ["smg", 6.0], ["revolver", 4.0], ["uzi", 4.0],
	["mammoth", 2.0], ["trident", 4.0]]
const PIL_TIME := 180.0              ## the 3-minute clock
const PIL_FIRST := 1.2               ## the first weapon
const PIL_EVERY := 10.0
const PIL_BOTS := 7                  ## setBotCfg: every pillar without a player gets a bot
## Godot-only modes (not in shared/modes.json, which `npm run content` regenerates from the web game).
const EXTRA_PATH := "res://data/extra/modes.json"
## Chaos needs room for 10: maps with at least 9 bot spots away from the player (bots + spawns) and wander >= 20.
const CHAOS_MAPS := ["arenaxl", "colosseum", "fortress", "rinkxl", "farm", "temple", "pirate", "rooftops"]
## Chaos events (CombatRng picks one every 15..25 s, never the same twice in a row). dur = seconds it lasts.
const CHAOS_EVENTS := {
	"crates": {"name": "Crate rain", "dur": 0.0},
	"gravity": {"name": "Low gravity", "dur": 8.0},
	"knockback": {"name": "Knockback storm", "dur": 10.0},
	"giant": {"name": "Giant", "dur": 12.0},
	"speed": {"name": "Speed surge", "dur": 8.0},
	"floor": {"name": "Floor quake", "dur": 9.0},
}
const CHAOS_ORDER := ["crates", "gravity", "knockback", "giant", "speed", "floor"]
const CHAOS_WARN := 3.0              ## the banner counts down this long before the event fires
const CHAOS_GAP := [15.0, 25.0]
const CHAOS_GRAV := 0.4
const CHAOS_KB := 2.5
const CHAOS_CRATES := 5
## MODES[k].maps (index.html ~3093 and ~3713-3727; not in shared/modes.json). [] = every level.
const TEAM_MAPS := ["arena", "park", "ice", "temple", "rooftops"]
const NEW_ARENAS := ["moonbase", "volcano", "candy", "pirate", "haunted", "beach", "farm", "crossroads", "donut", "chasm", "summit"]
const BIG_ARENAS := ["arenaxl", "rinkxl", "colosseum", "fortress"]
const MODE_MAPS := {"melee": ["arena", "park", "ice", "rooftops", "cloud", "tower", "brawlpit"] + NEW_ARENAS + BIG_ARENAS,
	"guns": ["arena", "temple", "rooftops", "gunrange"] + NEW_ARENAS + BIG_ARENAS,
	"ninja": ["dojo", "temple", "cloud", "rooftops", "tower", "arenaxl", "fortress"], "sandbox": ["custom"], "construction": ["siteyard"],
	"mega": ["shrink", "squeeze"], "pillars": ["pillars", "pillars2"], "lowg": ["craterdome", "capsule"],
	"giant": ["playroom"] + BIG_ARENAS, "explosive": ["blast", "arena", "park", "ice"] + BIG_ARENAS,
	"duel": TEAM_MAPS + ["colosseum", "fortress"] + NEW_ARENAS, "t2": TEAM_MAPS + ["colosseum", "fortress"] + NEW_ARENAS,
	"t3": TEAM_MAPS + BIG_ARENAS, "t4": TEAM_MAPS + BIG_ARENAS, "chaos": CHAOS_MAPS, "practice": ["practice", "test"]}
## MAP_ORDER (index.html ~3725): big open arenas first, then rooms and sky levels, the odd one-offs last. Arena lists follow it.
const MAP_ORDER := ["test", "practice", "dojo", "blast", "gunrange", "brawlpit", "siteyard", "craterdome", "capsule", "playroom",
	"arena", "park", "ice", "arenaxl", "rinkxl", "colosseum", "fortress", "temple", "farm", "rooftops", "tower", "shrink", "squeeze",
	"crossroads", "donut", "chasm", "summit", "moonbase", "candy", "haunted", "beach", "volcano", "pirate", "pillars", "pillars2", "custom"]
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
## Chaos state: next (s to the next warning), warn (s left on the countdown, 0 = none), id (the pending / running
## event), left (s the running event has left), last (the previous event), giant (the fighter made a giant), kb0 (the
## knockback setting to restore), floor (the floor kind forced). Empty = not Chaos.
var chaos := {}
## Pillars (`pil`): t (clock left), next (s to the next weapon), first, timeout (the clock ended it). Empty = not Pillars.
var pil := {}
## Online guest of a Godot host (net/net_match.gd sets it): the host decides the match end (`pend`) and runs the Chaos
## events (`gm` messages); this side only counts down and applies what the host says.
var remote := false

func _init(c: Combat) -> void:
	_combat = weakref(c)

## The K.O. limit a mode starts with (MODE_DEFAULTS + preset).
static func preset_limit(mode_id: String, modes: Dictionary) -> int:
	if mode_id == "sandbox": return SANDBOX_LIMIT
	return int(modes.get(mode_id, {}).get("preset", {}).get("limit", MODE_DEFAULTS["limit"]))

## How many bots a mode plays with (setBotCfg): teams force teams * 2 - 1, otherwise `requested` (0..12). flexTeams
## (Team Deathmatch) keeps the teams even: an odd bot count (requested, rounded up, 1..7).
static func bot_count(mode_id: String, modes: Dictionary, requested: int) -> int:
	var m: Dictionary = modes.get(mode_id, {})
	var t := int(m.get("teams", 0))
	if t and m.get("flexTeams", false):
		var n := clampi(requested, 1, 7)
		return n if n % 2 == 1 else n + 1
	if t: return t * 2 - 1
	var fx := fixed_bots(mode_id, modes)
	if fx >= 0: return fx
	return clampi(requested, 0, 12)

## Modes whose bot count is not the player's pick: Pillars (one bot per free pillar), the Practice Range (its 10
## dummies). -1 = the Players page decides.
static func fixed_bots(mode_id: String, modes: Dictionary) -> int:
	var m: Dictionary = modes.get(mode_id, {})
	if m.get("pillars", false): return PIL_BOTS
	if mode_id == "practice": return 10
	return -1

## The wizard's card line for a mode (BLURB, else the mode's desc).
static func blurb(mode_id: String, modes: Dictionary) -> String:
	return str(BLURB.get(mode_id, modes.get(mode_id, {}).get("desc", "")))

## Players per side for `bots` bots (team modes; 0 = free for all).
static func team_size(mode_id: String, modes: Dictionary, bots: int) -> int:
	var m: Dictionary = modes.get(mode_id, {})
	var t := int(m.get("teams", 0))
	if t and m.get("flexTeams", false): return (bots + 1) / 2
	return t

static func maps_for(mode_id: String) -> Array:
	if mode_id == "practice": return MODE_MAPS["practice"].duplicate()     # the Practice Range first, then the Test Map
	return sort_maps(MODE_MAPS.get(mode_id, []))

## `ids` in MAP_ORDER (unknown ids last, in their own order).
static func sort_maps(ids: Array) -> Array:
	var out := ids.duplicate()
	out.sort_custom(func(a: String, b: String) -> bool:
		var ia := MAP_ORDER.find(a); var ib := MAP_ORDER.find(b)
		if ia < 0: ia = 1000 + ids.find(a)
		if ib < 0: ib = 1000 + ids.find(b)
		return ia < ib)
	return out

## Adds the Godot-only modes (EXTRA_PATH) to `modes` (shared/modes.json) in place: keys already there win, allowFrom
## copies another mode's allowWeapons. Returns `modes`.
static func merge_extra(modes: Dictionary, path: String = EXTRA_PATH) -> Dictionary:
	if not FileAccess.file_exists(path): return modes
	var x: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (x is Dictionary): return modes
	for k: String in x:
		if k.begins_with("_") or modes.has(k) or not (x[k] is Dictionary): continue
		var m: Dictionary = (x[k] as Dictionary).duplicate(true)
		if not m.has("allowWeapons"):
			m["allowWeapons"] = (modes.get(str(m.get("allowFrom", "classic")), {}) as Dictionary).get("allowWeapons", []).duplicate()
		modes[k] = m
	return modes

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
	c.grav_setting = float(pre.get("grav", 1.0))               # pickMode: MODE_DEFAULTS.grav 1, Moon Drift's preset 0.15
	limit = p_limit if p_limit >= 0 else preset_limit(mode_id, c.modes)
	match_over = false; winner = null; end_t = 0.0
	chaos = {}
	pil = {}

## setBotCfg team split + loadMap's per-fighter reset (dashes, lives) + initLadder. `bots` in setup order.
func start_match(player: FighterState, bots: Array) -> void:
	var c := combat
	player.team = 0
	if c.teams and c.mode.get("flexTeams", false): c.teams = (bots.size() + 1) / 2     # Team Deathmatch: sides from the bot count
	for i in bots.size():
		var b: FighterState = bots[i]
		b.team = (0 if i < c.teams - 1 else 1) if c.teams else -1
	for f: FighterState in [player] + bots:
		f.dash_n = DASH_MAX; f.dash_regen = 0.0; f.dash_cd = 0.0; f.lives = c.lives_mode; f.elim = false
		f.phys.grav_scale = c.grav_setting                     # cfg.grav (Moon Drift)
	init_pillars()
	for f: FighterState in [player] + bots:                     # initLadder
		f.gg_rung = 0
		if c.mode_id == "gungame" and not f.is_ghost: gg_give(f)
	if c.mode.get("chaos", false):
		chaos = {"next": _chaos_gap() - CHAOS_WARN, "warn": 0.0, "id": "", "left": 0.0, "last": "", "giant": null, "kb0": c.kb_setting, "floor": ""}

## One life: a K.O. or a fall eliminates at once (Sudden Death).
func one_life() -> bool:
	return combat.lives_mode == 1 and bool(combat.mode.get("spectate", false))

## Fighters still in (not eliminated, not gone).
func survivors() -> Array:
	var out: Array = []
	for f: FighterState in combat.fighters:
		if not f.elim and not f.left: out.append(f)
	return out

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
	if remote: return
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
	var sub := "Most K.O.s when the clock ran out" if pil.get("timeout", false) else "Last one standing" if combat.lives_mode else ("Finished the Weapon Ladder" if combat.mode.get("ladder", false) else
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
	var spect := c.mode_id == "pillars" or online or bool(c.mode.get("spectate", false))    # the player watches the rest play on
	if f.is_player and spect and not match_over: c.ev({"type": "toast", "text": "You're out! Spectating."})
	if not match_over and not remote and c.lives_mode and (alive.size() <= 1 or (f.is_player and not spect)):
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

# ============================== Pillars ==============================

## initPillars: the 3-minute clock and the first weapon in 1.2 s (Pillars only).
func init_pillars() -> void:
	pil = {"t": PIL_TIME, "next": PIL_FIRST, "first": false, "timeout": false} if combat.mode_id == "pillars" else {}

## pillarGive: a random weapon (PIL_POOL weights) goes into the inventory; whatever was in the hand stays there.
func pillar_give(f: FighterState) -> void:
	var c := combat
	var tot := 0.0
	for e: Array in PIL_POOL: tot += e[1]
	var r := c.rng.next() * tot
	var key: String = PIL_POOL[0][0]
	for e: Array in PIL_POOL:
		r -= e[1]
		if r <= 0.0: key = e[0]; break
	var prev := f.slot
	c.pickup(f, key)
	if prev >= 0 and f.slots[prev] != null and f.slot != prev: c.equip_slot(f, prev)
	if f.is_player: c.ev({"type": "toast", "text": "New weapon: " + str(c.wdata(key).get("name", key))})

## updatePillars: the weapon handout every 10 s and the clock (online only the host calls time).
func update_pillars(dt: float) -> void:
	if pil.is_empty() or match_over: return
	var c := combat
	pil["t"] -= dt; pil["next"] -= dt
	if pil["next"] <= 0.0:
		pil["next"] = PIL_EVERY
		for f: FighterState in c.fighters:
			if not f.dead and not f.elim and not f.is_ghost and not f.left: pillar_give(f)
		pil["first"] = true
	if pil["t"] <= 0.0 and not (c.net_started and not c.net_host):
		var w: FighterState = null                 # most K.O.s, then fewest deaths, first in fighter order
		for f: FighterState in c.fighters:
			if f.left or (f.is_ghost and not (c.net_host and f.net_human)): continue     # online: the guests count too
			if w == null or f.ko > w.ko or (f.ko == w.ko and int(f.st["deaths"]) < int(w.st["deaths"])): w = f
		if w != null:
			pil["timeout"] = true
			end_match(w)

## "2:41" for the Pillars clock.
func pillars_clock() -> String:
	var t := maxi(0, ceili(float(pil.get("t", 0.0))))
	return "%d:%02d" % [t / 60, t % 60]

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

# ============================== Chaos events ==============================

func _chaos_gap() -> float:
	return CHAOS_GAP[0] + combat.rng.next() * (CHAOS_GAP[1] - CHAOS_GAP[0])

## Can `id` run on this match? (the floor event needs tiles that move: wobble / tilt / quake)
func chaos_ok(id: String, dyn: ArenaDyn) -> bool:
	if id == "floor": return dyn != null and dyn.can_force()
	return true

## Every CHAOS_GAP seconds: pick an event (not the last one), count down CHAOS_WARN, run it, restore the rules.
## Cheap: a few float compares per step; the events touch each fighter once at start and once at the end.
func update_chaos(dt: float, pickups: Pickups, dyn: ArenaDyn) -> void:
	var s := chaos
	if match_over:
		if s["id"] != "" and s["left"] > 0.0: _chaos_end(dyn)
		return
	if remote:                                            # the host picks and starts the events (chaos_remote)
		if s["warn"] > 0.0: s["warn"] = maxf(0.0, s["warn"] - dt)
		if s["left"] > 0.0:
			s["left"] -= dt
			if s["left"] <= 0.0: _chaos_end(dyn)
		return
	if s["left"] > 0.0:
		s["left"] -= dt
		if s["id"] == "speed":                            # newcomers (respawns) get the surge too; it runs out with the event
			for f: FighterState in combat.fighters:
				if not f.dead and f.spd_t < s["left"]: f.spd_t = s["left"]
		if s["left"] <= 0.0: _chaos_end(dyn)
		return
	if s["warn"] > 0.0:
		s["warn"] -= dt
		if s["warn"] <= 0.0:
			s["warn"] = 0.0
			_chaos_start(s["id"], pickups, dyn)
		return
	s["next"] -= dt
	if s["next"] > 0.0: return
	var pool: Array = []
	for id: String in CHAOS_ORDER:
		if id != s["last"] and chaos_ok(id, dyn): pool.append(id)
	var pick: String = pool[int(floor(combat.rng.next() * pool.size()))]
	if pick == "floor": s["floor"] = dyn.force_kind()
	s["id"] = pick; s["warn"] = CHAOS_WARN
	combat.ev({"type": "chaos_warn", "id": pick, "name": chaos_name(pick), "in": CHAOS_WARN})

## The event's display name ("Floor quake" says which floor it forces).
func chaos_name(id: String) -> String:
	if id == "floor": return "Floor " + (str(chaos.get("floor", "")) if str(chaos.get("floor", "")) != "" else "quake")
	return str(CHAOS_EVENTS.get(id, {}).get("name", id))

## Online guest: the host's Chaos message. `k` = "cw" (warning: id, floor), "cs" (started: id, giant), "ce" (ended).
func chaos_remote(k: String, id: String, fl: String, giant: FighterState, dyn: ArenaDyn) -> void:
	var s := chaos
	if s.is_empty() or match_over or not CHAOS_EVENTS.has(id): return
	match k:
		"cw":
			if s["left"] > 0.0: _chaos_end(dyn)
			s["id"] = id; s["floor"] = fl; s["warn"] = CHAOS_WARN
			combat.ev({"type": "chaos_warn", "id": id, "name": chaos_name(id), "in": CHAOS_WARN})
		"cs":
			if s["left"] > 0.0 and s["id"] != id: _chaos_end(dyn)
			if s["left"] > 0.0: return
			s["id"] = id; s["floor"] = fl; s["warn"] = 0.0
			_chaos_start(id, null, dyn, giant)
		"ce":
			if s["left"] > 0.0 and s["id"] == id: _chaos_end(dyn)
	if remote: s["next"] = INF

func _chaos_start(id: String, pickups: Pickups, dyn: ArenaDyn, forced_giant: FighterState = null) -> void:
	var c := combat
	var s := chaos
	var dur: float = CHAOS_EVENTS[id]["dur"]
	match id:
		"crates":                                          # several random-weapon crates at once (free spots only)
			if pickups != null and not pickups.no_crates and not remote:
				for i in CHAOS_CRATES:
					var k := pickups.pick_crate_key()
					if k != "": pickups.spawn_drop(k)
		"gravity":
			for f: FighterState in c.fighters: f.phys.grav_scale = CHAOS_GRAV
		"knockback":
			s["kb0"] = c.kb_setting
			c.kb_setting = (c.kb_setting if c.kb_setting != 0.0 else 1.0) * CHAOS_KB
		"giant":
			var pool: Array = []
			for f: FighterState in c.fighters:
				if not f.dead and not f.elim and (not f.is_ghost or (c.net_host and f.net_human)): pool.append(f)
			if remote: pool = [forced_giant] if forced_giant != null else []
			if pool.is_empty(): dur = 0.0
			else:
				var g: FighterState = pool[int(floor(c.rng.next() * pool.size()))]
				g.big_t = dur; g.hp = c.max_hp(g)
				s["giant"] = g
		"speed":
			for f: FighterState in c.fighters:
				if not f.dead: f.spd_t = maxf(f.spd_t, dur)
		"floor":
			if dyn != null: dyn.force(str(s["floor"]), dur)
	s["left"] = dur
	var ev := {"type": "chaos", "id": id, "name": chaos_name(id), "dur": dur}
	if id == "giant" and s["giant"] != null: ev["f"] = s["giant"]
	c.ev(ev)
	if dur <= 0.0: _chaos_end(dyn)

## Back to the normal rules.
func _chaos_end(dyn: ArenaDyn) -> void:
	var c := combat
	var s := chaos
	var id: String = s["id"]
	match id:
		"gravity":
			for f: FighterState in c.fighters: f.phys.grav_scale = c.grav_setting
		"knockback":
			c.kb_setting = s["kb0"]
		"giant":
			var g: FighterState = s["giant"]
			if g != null:
				g.big_t = 0.0; g.hp = minf(g.hp, c.max_hp(g))
			s["giant"] = null
		"floor":
			if dyn != null: dyn.force("", 0.0)
	s["left"] = 0.0; s["last"] = id; s["id"] = ""; s["floor"] = ""
	s["next"] = INF if remote else _chaos_gap() - CHAOS_WARN
	c.ev({"type": "chaos_end", "id": id})

## The Chaos HUD bit: "Crate rain in 3" / "Low gravity 6s" ("" = nothing pending).
func chaos_text() -> String:
	var s := chaos
	if s.is_empty() or match_over: return ""
	if s["warn"] > 0.0: return "%s in %d" % [chaos_name(s["id"]), ceili(s["warn"])]
	if s["left"] > 0.0: return "%s %ds" % [chaos_name(s["id"]), ceili(s["left"])]
	return ""

# ============================== per step ==============================

## simStep's mode updates (updatePotato / updatePillars / updateShrink) plus the end-of-match countdown.
func update(dt: float, pickups: Pickups = null, dyn: ArenaDyn = null) -> void:
	update_pillars(dt)
	update_shrink(dt, pickups)
	if not chaos.is_empty(): update_chaos(dt, pickups, dyn)
	if end_t > 0.0:
		end_t -= dt
		if end_t <= 0.0:
			end_t = 0.0
			combat.ev({"type": "match_finished", "winner": winner, "won": player_won(winner)})

## The mode line under the K.O. counter (updateModeHud + updateKoText), "" = nothing to show.
func hud_text(player: FighterState, with_teams := true) -> String:
	var c := combat
	if player == null: return ""
	var t := ""
	if c.mode.get("spectate", false):                       # Sudden Death: in or out, and how many are left
		t = ("♥" if not player.elim else "OUT") + "  ·  %d left" % survivors().size()
	elif c.mode_id == "pillars":                           # updateKoText: the K.O. count (one life, no hearts)
		t = ("OUT" if player.elim else "%d K.O.s" % player.ko) + "  ·  %d left" % survivors().size()
	elif not c.brawl:                                       # the Practice Range's dummies
		t = "Practice  ·  %d K.O.s" % player.ko
	elif c.lives_mode:
		t = "♥".repeat(player.lives) if player.lives > 0 else "OUT"
	elif c.teams:
		if with_teams:                                      # the world draws a TeamBoard instead (colour chips); text kept for tests/fallback
			var mine := player.team
			t = "Team %d v %d" % [team_ko(mine), team_ko(1 - mine)] + (" / %d" % limit if limit else "")
	elif limit:
		t = "%d / %d K.O.s" % [player.ko, limit]
	var extra := ""
	if c.mode_id == "gungame" and not match_over:
		extra = "Weapon %d of %d · %s" % [player.gg_rung + 1, GG.size(), c.wdata(GG[player.gg_rung]).get("name", "Spatula")]
	elif not pil.is_empty() and not match_over:
		extra = "%s  ·  New weapon in %d" % [pillars_clock(), maxi(0, ceili(float(pil["next"])))]
	elif chaos_text() != "":
		extra = "⚡ " + chaos_text()
	elif not shrink.is_empty() and not match_over:
		var s := shrink
		extra = "Arena %dm" % Combat.js_round(s["size"]) + (" · shrinking soon" if s["hold"] > 0.0 else (" · growing" if s["dir"] == 1 else (" · smallest" if s["size"] <= s["min"] else "")))
	if dash_gear(player) and not player.dead:
		extra += ("   " if extra != "" else "") + "Dash " + "◆".repeat(player.dash_n) + "◇".repeat(DASH_MAX - player.dash_n)
	var bh := Skills.burst_hud(c, player) if not player.dead else []   # weapon_tuning.json burst pool of the held weapon
	if bh.size() > 0:
		extra += ("   " if extra != "" else "") + "Shots " + "◆".repeat(bh[0]) + "◇".repeat(bh[1] - bh[0])
	return t if extra == "" else (t + "   " + extra if t != "" else extra)
