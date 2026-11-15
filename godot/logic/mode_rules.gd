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
## Godot-only modes (res://data/extra/modes.json, merged by merge_extra: Team Deathmatch (tdm: two teams sized by the
## Players page, team limit 30), Deathmatch (deathmatch: free for all to 20), Sudden Death (sudden: one life, a K.O. or
## a fall eliminates, the player spectates until one fighter stands), Chaos (chaos: 5 v 5 to 50 with random events),
## Capture the Flag (ctf, logic/ctf.gd: two teams, one flag, hold it 30 s or most hold time on the 5:00 clock; offline only).
## DLC packs may add or extend modes too: every pack.json `modes` section is merged after the built-in file.
## Explosive: launchers only, always 300 health. Moon Drift
## (lowg): its preset gravity 0.15 goes to Combat.grav_setting and every fighter's FighterPhysics.grav_scale (projG and
## the gentler jump follow from it). Practice Range (practice, the web PRACTICE button): the range maps' dummies
## (PracticeRange), no score.
## Sandbox (sandbox, offline only like the web game): build your own arena on 'custom' (SandboxLayout, ui/build_hud.gd),
## then Play runs a free for all with bots on it, first to SANDBOX_LIMIT K.O.s.
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
	"tdm", "deathmatch", "sudden", "chaos", "ctf", "explosive", "lowg", "practice", "sandbox"]
## Offline only (the web netMode sends Sandbox and Construction matches online as Classic).
const OFFLINE_ONLY := ["sandbox", "construction", "ctf"]
const SANDBOX_LIMIT := 10            ## a test run on your arena ends at this many K.O.s (the web Sandbox has no limit)
## Offline brawl modes whose data preset is "no K.O. limit" (the web menu's 0 button). Auto now gives them a win
## condition instead of an endless match; an explicit 0 in Settings (or --limit=0) still means no limit.
const LIMITLESS_BRAWL := ["classic", "melee", "guns", "ninja", "explosive", "giant", "lowg", "construction"]
const LIMITLESS_DEFAULT := 20        ## K.O.s Auto plays these modes to (the web menu's 20 button)
## Short card line per mode: data/extra/wizard.json `short` (word for word the web menu's BLURB, see docs/WRITING.md).
const WIZARD_PATH := "res://data/extra/wizard.json"
static var _shorts: Dictionary = {}
## Godot-only modes (not in shared/modes.json, which `npm run content` regenerates from the web game).
const EXTRA_PATH := "res://data/extra/modes.json"
## Chaos needs room for 10: maps with at least 9 bot spots away from the player (bots + spawns) and wander >= 20.
## Capture the Flag: big maps with an open, walkable middle (tests/ctf_test.gd checks the stand on every one).
const CTF_MAPS := ["crossroads", "donut", "fortress", "colosseum", "farm", "arenaxl"]
const CHAOS_MAPS := ["arenaxl", "colosseum", "fortress", "rinkxl", "farm", "temple", "pirate", "rooftops"]
## Chaos events (CombatRng picks one every 15..25 s, never the same twice in a row). dur = seconds it lasts.
const CHAOS_EVENTS := {
	"crates": {"name": "Crate rain", "dur": 0.0},
	"gravity": {"name": "Low gravity", "dur": 8.0},
	"knockback": {"name": "Knockback storm", "dur": 10.0},
	"giant": {"name": "Giant time", "dur": 12.0},
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
	"ninja": ["dojo", "temple", "cloud", "rooftops", "tower", "arenaxl", "fortress"], "sandbox": ["custom"], "construction": ["siteyard", "sitegen"],
	"mega": ["shrink", "squeeze"], "lowg": ["craterdome", "capsule"],
	"giant": ["playroom"] + BIG_ARENAS, "explosive": ["blast", "arena", "park", "ice"] + BIG_ARENAS,
	"duel": TEAM_MAPS + ["colosseum", "fortress"] + NEW_ARENAS, "t2": TEAM_MAPS + ["colosseum", "fortress"] + NEW_ARENAS,
	"t3": TEAM_MAPS + BIG_ARENAS, "t4": TEAM_MAPS + BIG_ARENAS, "chaos": CHAOS_MAPS, "ctf": CTF_MAPS, "practice": ["practice", "test"]}
## MAP_ORDER (index.html ~3725): big open arenas first, then rooms and sky levels, the odd one-offs last. Arena lists follow it.
const MAP_ORDER := ["test", "practice", "dojo", "blast", "gunrange", "brawlpit", "siteyard", "sitegen", "craterdome", "capsule", "playroom",
	"arena", "park", "ice", "arenaxl", "rinkxl", "colosseum", "fortress", "temple", "farm", "rooftops", "tower", "shrink", "squeeze",
	"crossroads", "donut", "chasm", "summit", "moonbase", "candy", "haunted", "beach", "volcano", "pirate", "custom"]
## The shrinking floors (MAPS.shrink / MAPS.squeeze build(): `shrink = {...}`); the floor is the map's first box.
const SHRINK := {
	"shrink": {"S0": 64.0, "min": 16.0, "max": 40.0, "both": true, "D": 64.0, "rate": 55.0},
	"squeeze": {"S0": 80.0, "min": 22.0, "max": 58.0, "both": false, "D": 36.0, "rate": 34.0},
}

var _combat: WeakRef                 ## weak: Combat owns this object
var combat: Combat:
	get: return _combat.get_ref()
var limit := 0                       ## cfg.limit: K.O.s (team K.O.s in team modes) to win, 0 = no limit
var timeout_tie := false             ## Capture the Flag: the clock ended it level
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
## Capture the Flag (logic/ctf.gd): the flag, its carrier and hold timers. null = not CTF.
var ctf: CtfRules = null
## Online guest of a Godot host (net/net_match.gd sets it): the host decides the match end (`pend`) and runs the Chaos
## events (`gm` messages); this side only counts down and applies what the host says.
var remote := false

func _init(c: Combat) -> void:
	_combat = weakref(c)

## The K.O. limit a mode starts with (MODE_DEFAULTS + preset). A brawl mode whose preset limit is 0 and that has no
## other end condition (lives, ladder, clock) gets LIMITLESS_DEFAULT, so Auto is a real match rather than an endless one.
static func preset_limit(mode_id: String, modes: Dictionary) -> int:
	if mode_id == "sandbox": return SANDBOX_LIMIT
	var n := int(modes.get(mode_id, {}).get("preset", {}).get("limit", MODE_DEFAULTS["limit"]))
	if n <= 0 and LIMITLESS_BRAWL.has(mode_id): return LIMITLESS_DEFAULT
	return n

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

## Modes whose bot count is not the player's pick: the Practice Range (its 10
## dummies). -1 = the Players page decides.
static func fixed_bots(mode_id: String, modes: Dictionary) -> int:
	if mode_id == "practice": return 10
	return -1

## The card line for a mode (wizard.json `short`, else the mode's desc).
static func blurb(mode_id: String, modes: Dictionary) -> String:
	if _shorts.is_empty():
		var f := FileAccess.open(WIZARD_PATH, FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text()) if f else null
		if d is Dictionary:
			for k in d.get("modes", {}):
				_shorts[k] = str(d["modes"][k].get("short", ""))
	var s := str(_shorts.get(mode_id, ""))
	return s if s != "" else str(modes.get(mode_id, {}).get("desc", ""))

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

## Adds the Godot-only modes to `modes` (shared/modes.json) in place: keys already there win, allowFrom copies another
## mode's allowWeapons. `path` overrides the built-in file (default EXTRA_PATH); the DLC packs' `modes` sections join an
## EXTRA_PATH merge only, in deterministic (sorted pack id) order: e.g. construction/modes.json extends the shared
## construction mode with the 9 DLC tools and their crate weights. Returns `modes`.
static func merge_extra(modes: Dictionary, path: String = EXTRA_PATH) -> Dictionary:
	_merge_modes_file(modes, path)
	if path == EXTRA_PATH:
		for f: String in _pack_mode_paths():
			_merge_modes_file(modes, f)
	return modes

## Every DLC pack's `modes` section file, in the Content pack registry's deterministic order ([] without a registry).
static func _pack_mode_paths() -> Array:
	var content: Variant = load("res://autoload/content.gd")
	var paths: Variant = content.pack_paths("modes") if content != null else []
	return paths if paths is Array else []

static func _merge_modes_file(modes: Dictionary, path: String) -> void:
	if not FileAccess.file_exists(path): return
	var x: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (x is Dictionary): return
	for k: String in x:
		if k.begins_with("_") or not (x[k] is Dictionary): continue
		if modes.has(k):
			# Additive hooks: extend an existing mode's weapon list and crate weights with Godot-only extras.
			var src: Dictionary = x[k]
			var dst: Dictionary = modes[k]
			if src.has("allowWeapons") and dst.get("allowWeapons") is Array:
				for w in src["allowWeapons"]:
					if not dst["allowWeapons"].has(w):
						dst["allowWeapons"].append(w)
			if src.get("dropWeights") is Dictionary:
				var weights: Dictionary = dst.get("dropWeights", {})
				for w: String in src["dropWeights"]:
					weights[w] = float(src["dropWeights"][w])
				dst["dropWeights"] = weights
			continue
		var m: Dictionary = (x[k] as Dictionary).duplicate(true)
		if not m.has("allowWeapons"):
			m["allowWeapons"] = (modes.get(str(m.get("allowFrom", "classic")), {}) as Dictionary).get("allowWeapons", []).duplicate()
		modes[k] = m

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
	if m.get("ctf", false): limit = 0                           # Capture the Flag ends on the 30 s hold or the clock, never on K.O.s
	match_over = false; winner = null; end_t = 0.0
	chaos = {}
	ctf = null

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
	for f: FighterState in [player] + bots:                     # initLadder
		f.gg_rung = 0
		if c.mode_id == "gungame" and not f.is_ghost: gg_give(f)
	if c.mode.get("ctf", false): ctf = CtfRules.new(c)
	if c.mode.get("chaos", false):
		chaos = {"next": _chaos_gap() - CHAOS_WARN, "warn": 0.0, "id": "", "left": 0.0, "last": "", "giant": null, "kb0": c.kb_setting, "floor": ""}

## A fighter went down (K.O. or ring-out): the flag drops (CtfRules.on_down). `fell` = off the map.
func on_down(f: FighterState, fell: bool) -> void:
	if ctf != null: ctf.on_down(f, fell)

## MatchSim.setup, once the map and its solids exist: the Capture the Flag stand.
func ctf_setup(map: Dictionary, solids: Array, ring_out_y: float) -> void:
	if ctf != null: ctf.setup(map, solids, ring_out_y)

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
	if combat.teams: title = tr("YOUR TEAM WINS!") if won else tr("ENEMY TEAM WINS!")
	else: title = tr("YOU WIN!") if w.is_player else tr("%s WINS!") % w.name.to_upper()
	var sub := ctf.sub_text() if ctf != null else tr("Last wobbler standing") if combat.lives_mode else (tr("Finished the Weapon Ladder") if combat.mode.get("ladder", false) else
		(tr("First team to %d K.O.s") if combat.teams else tr("First to %d K.O.s")) % limit)
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
	var spect := online or bool(c.mode.get("spectate", false))    # the player watches the rest play on
	if f.is_player and spect and not match_over: c.ev({"type": "toast", "text": tr("You're out! Spectating from the sofa.")})
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
		combat.ev({"type": "toast", "text": tr("Weapon %d of %d: %s") % [killer.gg_rung + 1, GG.size(), tr(str(combat.wdata(GG[killer.gg_rung]).get("name", "Spatula")))]})

# ============================== ninja dash ==============================

## dashGear: only while holding a ninja weapon.
func dash_gear(f: FighterState) -> bool:
	return f.slot >= 0 and DASH_GEAR.has(f.weapon)

## doDash: a burst of speed toward (ix, iz) (the facing when there is no input). 3 charges.
func do_dash(f: FighterState, ix: float, iz: float) -> bool:
	if not dash_gear(f) or f.dead or f.down_t > 0.0 or f.trap_t > 0.0 or f.dash_n <= 0 or f.dash_cd > 0.0: return false
	var l := sqrt(ix * ix + iz * iz)
	if l < 0.05:
		ix = sin(f.yaw); iz = cos(f.yaw); l = 1.0
	var p := f.phys
	p.vx = ix / l * 24.0; p.vz = iz / l * 24.0
	if p.grounded: p.vy = maxf(p.vy, 1.2)
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
		combat.ev({"type": "toast", "text": tr("Arena reset at half size! Cosy")})
	else:                                   # at its smallest: a short breather, then it starts growing again
		s["rest"] = (5.0 if s["rest"] < 0.0 else s["rest"]) - dt
		if s["rest"] <= 0.0:
			s["rest"] = -1.0; s["dir"] = 1
			combat.ev({"type": "toast", "text": tr("The arena is growing! Room to wobble")})
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
	if shrink.has("spots"):                 # Construction Arcade (dlc/construction/stage_events.gd): the map's own crate spots that are still on the floor
		return (shrink["spots"] as Array).filter(func(sp: Array) -> bool: return absf(sp[0]) <= r + 2.5 and absf(sp[1]) <= r + 2.5)
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
	if id == "floor": return tr("Floor %s") % tr(str(chaos.get("floor", "")) if str(chaos.get("floor", "")) != "" else "quake")
	return tr(str(CHAOS_EVENTS.get(id, {}).get("name", id)))

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
	if s["warn"] > 0.0: return tr("%s in %d") % [chaos_name(s["id"]), ceili(s["warn"])]
	if s["left"] > 0.0: return tr("%s %ds") % [chaos_name(s["id"]), ceili(s["left"])]
	return ""

# ============================== per step ==============================

## simStep's mode updates (updatePotato / updateShrink) plus the end-of-match countdown.
func update(dt: float, pickups: Pickups = null, dyn: ArenaDyn = null) -> void:
	update_shrink(dt, pickups)
	if ctf != null: ctf.update(dt)
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
		t = tr("Out · %d left") % survivors().size() if player.elim else tr("Alive · %d left") % survivors().size()
	elif not c.brawl:                                       # the Practice Range's dummies
		t = tr("Practice · %d K.O.s") % player.ko
	elif c.lives_mode:
		t = tr("Lives %d") % player.lives if player.lives > 0 else tr("Out")
	elif ctf != null:                                       # Capture the Flag: the flag line below stands in for the score
		pass
	elif c.teams:
		if with_teams:                                      # the world draws a TeamBoard instead (colour chips); text kept for tests/fallback
			var mine := player.team
			t = tr("Team %d v %d / %d") % [team_ko(mine), team_ko(1 - mine), limit] if limit else tr("Team %d v %d") % [team_ko(mine), team_ko(1 - mine)]
	elif limit:
		t = tr("%d / %d K.O.s") % [player.ko, limit]
	var extra := ""
	if c.mode_id == "gungame" and not match_over:
		extra = tr("Weapon %d of %d · %s") % [player.gg_rung + 1, GG.size(), tr(str(c.wdata(GG[player.gg_rung]).get("name", "Spatula")))]
	elif ctf != null and not match_over:
		extra = ctf.hud_text()
	elif chaos_text() != "":
		extra = tr("Event: %s") % chaos_text()
	elif not shrink.is_empty() and not match_over:
		var s := shrink
		var sz := Combat.js_round(s["size"])
		if s["hold"] > 0.0: extra = tr("Arena %dm · shrinking soon") % sz
		elif s["dir"] == 1: extra = tr("Arena %dm · growing") % sz
		elif s["size"] <= s["min"]: extra = tr("Arena %dm · smallest") % sz
		else: extra = tr("Arena %dm") % sz
	if dash_gear(player) and not player.dead:
		extra += ("   " if extra != "" else "") + tr("Dash") + " " + "+".repeat(player.dash_n) + "-".repeat(DASH_MAX - player.dash_n)
	var bh := Skills.burst_hud(c, player) if not player.dead else []   # weapon_tuning.json burst pool of the held weapon
	if bh.size() > 0:
		extra += ("   " if extra != "" else "") + tr("Shots") + " " + "+".repeat(bh[0]) + "-".repeat(bh[1] - bh[0])
	return t if extra == "" else (t + "   " + extra if t != "" else extra)
