class_name QuickPlay
extends RefCounted
## The title's Quick play button: one tap starts an all-random offline match, no wizard. pick() chooses a game type the
## port plays offline and is fun cold (ModeRules.PLAYABLE minus the Practice Range, Sandbox and Construction), an arena
## that game type allows, a class you own, a floor kind, a bot count and a bot skill, and returns the `over` dictionary
## scripts/main.gd hands to play_offline ({mode, map, bots, difficulty}) plus `class` and `dyn` (the world reads those
## from Settings; main.gd writes them first, the Construction hub's pattern).
## The picks are checked against the loaded content (Content / Dynamics) so nothing invalid can reach the match; a
## broken content table still yields a playable fallback instead of an empty arena.

const NOT_QUICK := ["practice", "sandbox", "construction"]   ## the range's dummies, the Sandbox, the DLC site
const DEV_MAPS := ["test", "practice", "custom"]             ## the test level, the range, the Sandbox arena
const BOT_MIN := 1
const BOT_MAX := 7

## The game types a quick match can roll, in the wizard's order.
static func modes() -> Array:
	var out: Array = []
	for m: String in ModeRules.PLAYABLE:
		if NOT_QUICK.has(m) or not Content.modes.has(m) or out.has(m): continue
		out.append(m)
	if out.is_empty() and Content.modes.has("classic"): out.append("classic")
	return out

## The arenas that mode allows, minus the dev / range maps.
static func maps_for(mode: String) -> Array:
	var out: Array = []
	for id: String in SetupWizard.maps_for(mode):
		if DEV_MAPS.has(id) or not Content.maps.has(id) or out.has(id): continue
		out.append(id)
	return out

## The playable classes you own.
static func classes() -> Array:
	var out: Array = []
	for id: String in Content.classes.keys():
		if SetupWizard.owns_class(id): out.append(id)
	out.sort()
	return out

## The bot skills the world knows.
static func difficulties() -> Array:
	var out: Array = []
	for d: String in SetupWizard.DIFFS:
		if Content.difficulties.has(d): out.append(d)
	if out.is_empty(): out = Content.difficulties.keys()
	return out

## The dynamic-arena kinds ("off", "random", wobble, tilt, quake, drift).
static func floors() -> Array:
	return Dynamics.KINDS.duplicate()

## One random `over` dictionary for play_offline (plus `class` / `dyn`, which main.gd writes to Settings first). `rng`
## is the caller's own RandomNumberGenerator: the same seed picks the same match, and combat.rng is never touched.
static func pick(rng: RandomNumberGenerator) -> Dictionary:
	var mode := _pick(rng, modes(), "classic")
	var map := _pick(rng, maps_for(mode), "arena")
	var cls := _pick(rng, classes(), "wobbler")
	var diff := _pick(rng, difficulties(), "normal")
	var floor_kind := _pick(rng, floors(), "off")
	var bots := ModeRules.bot_count(mode, Content.modes, _range(rng, BOT_MIN, BOT_MAX))
	# final guard: never hand the world an id it would have to fix up (an empty or stale content table)
	if not Content.modes.has(mode): mode = "classic" if Content.modes.has("classic") else str(Content.modes.keys()[0])
	if not Content.maps.has(map): map = _fallback_map()
	if not Content.classes.has(cls) or not SetupWizard.owns_class(cls): cls = "wobbler" if Content.classes.has("wobbler") else str(Content.classes.keys()[0])
	if not Content.difficulties.has(diff): diff = "normal" if Content.difficulties.has("normal") else str(Content.difficulties.keys()[0])
	if not Dynamics.KINDS.has(floor_kind): floor_kind = "off"
	return {"mode": mode, "map": map, "bots": bots, "difficulty": diff, "class": cls, "dyn": floor_kind}

static func _fallback_map() -> String:
	for id: String in ["arena", "park", "ice"]:
		if Content.maps.has(id): return id
	return str(Content.maps.keys()[0])

static func _pick(rng: RandomNumberGenerator, values: Array, fallback: String) -> String:
	if values.is_empty(): return fallback
	return str(values[_range(rng, 0, values.size() - 1)])

static func _range(rng: RandomNumberGenerator, lo: int, hi: int) -> int:
	if rng == null: return lo
	return rng.randi_range(lo, hi)
