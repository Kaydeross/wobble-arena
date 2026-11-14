extends Node
## Sound effects (autoload `Sfx`). Every recipe of the web game's synth (public/index.html `SOUNDS`) is pre-rendered by
## tools/render-sfx.js into res://audio/sfx/<name>.wav (see docs/AUDIO.md). `Sfx.play(name, volume, priority)` takes the
## next free player of a fixed pool (no allocation per call). Each play gets a small random pitch / volume shift so a
## burst of the same effect does not sound like one machine; when every player is busy the pool may only cut a sound
## with the same or a lower priority, so rapid rifle fire never swallows a boom, a rocket or a K.O. stinger.
## Settings: `volume` (0..1, the web game's settings.vol) on the Master bus, `muted` skips playback.

## Every name in the JS SOUNDS table that this client plays, in the order tools/render-sfx.js renders them (tests check
## each one has a stream). The last group are the big-moment cues added for Godot (the web game does not play them).
const NAMES: PackedStringArray = ["click", "pop", "whack", "clink", "slap", "swing", "shot", "shotgun", "flame",
	"mammoth", "sniper", "rocket", "boom", "wind", "kick", "boing", "bounce", "pickup", "drop", "mag", "shellIn",
	"hover", "jump", "dash", "land", "step", "ko", "fall", "respawn", "countdown", "win", "lose", "lowhp"]
const DIR := "res://audio/sfx/"
const POOL := 12
const BUS := "SFX"                 ## every effect plays on this bus (volume: Settings `sfx_volume`)

## How important a sound is when all 12 players are busy (0 = ordinary, 1 = a long stinger / a cue that matters,
## 2 = a match-defining moment). A full pool can only ever cut a sound of the same or a lower priority, and an
## important sound with no slot left at all is dropped rather than cutting another important one — this mirrors the
## web engine's `pri` / voice-cap rule. Names not listed are 0.
const PRIORITY := {
	"boom": 2, "ko": 2, "win": 2, "lose": 2,
	"rocket": 1, "sniper": 1, "mammoth": 1, "fall": 1, "respawn": 1, "countdown": 1, "lowhp": 1,
}
const PITCH_VARY := 0.04           ## +-4 % pitch per play: the web game's `vary`, kept small so a weapon keeps its voice
const VOL_DB_VARY := 1.5           ## +-1.5 dB per play: the same rhythm no longer sounds like one sample

var streams := {}                  ## name -> AudioStreamWAV
var _pool: Array[AudioStreamPlayer] = []
var _prio := PackedInt32Array()    ## per player: priority of the sound it is playing (0 = ordinary)
var _since := PackedInt64Array()   ## per player: ticks (ms) it was started (the oldest is cut first)
var _next := 0
var _muted := false
var _shot_t := {}                  ## fighter instance id -> sim time of its last shot sound
var _busy_until := 0               ## ticks (ms) when the last started sound ends (see _exit_tree)
var _unlocked := false             ## a user gesture has happened (web audio needs one)
var _rng := RandomNumberGenerator.new()   ## pitch / volume jitter; its own RNG so the game's RNG stream stays untouched

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for n in NAMES:
		var s: AudioStream = load(DIR + n + ".wav")
		if s: streams[n] = s
		else: push_warning("Sfx: missing stream " + n)
	if AudioServer.get_bus_index(BUS) < 0:      # the sound-effects bus (Settings `sfx_volume`), sent to Master
		AudioServer.add_bus()
		var b := AudioServer.bus_count - 1
		AudioServer.set_bus_name(b, BUS)
		AudioServer.set_bus_send(b, "Master")
	_prio.resize(POOL)
	_since.resize(POOL)
	_rng.randomize()
	for i in POOL:
		var p := AudioStreamPlayer.new()
		p.bus = BUS
		p.name = "Sfx%d" % i
		add_child(p)
		_pool.append(p)
	_apply_settings()
	Settings.changed.connect(_on_setting)

## Plays one sound effect; `volume` scales it (linear, 1 = as rendered) and `priority` overrides the table above
## (-1 = use the sound's own priority). Unknown names are ignored like the JS sfx().
func play(sfx_name: String, volume := 1.0, priority := -1) -> void:
	if _muted or volume <= 0.0: return
	var s: AudioStream = streams.get(sfx_name)
	if s == null: return
	var pr := priority if priority >= 0 else int(PRIORITY.get(sfx_name, 0))
	var i := _free_player(pr)
	if i < 0: return                    # every slot is taken by something at least as important: drop this one
	var p := _pool[i]
	p.stream = s
	p.volume_db = linear_to_db(volume) + _rng.randf_range(-VOL_DB_VARY, VOL_DB_VARY)
	p.pitch_scale = 1.0 + _rng.randf_range(-PITCH_VARY, PITCH_VARY)
	p.play()
	_prio[i] = pr
	_since[i] = Time.get_ticks_msec()
	_busy_until = maxi(_busy_until, _since[i] + int(s.get_length() * 1000.0 / p.pitch_scale))

## Index of a free player, else the oldest one whose priority `pr` may cut (-1 = nothing may be cut).
## No allocation: the pool is a fixed array and everything below indexes it.
func _free_player(pr: int) -> int:
	var victim := -1
	for k in POOL:
		var i := (_next + k) % POOL
		if not _pool[i].playing:
			_next = (i + 1) % POOL
			return i
		if _prio[i] <= pr and (victim < 0 or _prio[i] < _prio[victim] or (_prio[i] == _prio[victim] and _since[i] < _since[victim])):
			victim = i
	if victim < 0: return -1
	_next = (victim + 1) % POOL
	return victim

## Combat/MatchSim/Pickups events -> sounds, at the points where the web game calls sfx() (World drains every event
## through here). Explicit "sfx" events already carry the JS name (topple boing, kick, kick/shove whack, melee swing,
## melee hitSfx, knife throw swing, knife clink). A "swing" with no swing animation running is the dash / air-recover
## whoosh (do_dash, Skills.do_recover) and gets the movement dash instead of a melee swing, so it never plays twice.
func on_event(e: Dictionary, sim: MatchSim) -> void:
	var f: FighterState = e.get("f") if e.get("f") is FighterState else null
	match String(e["type"]):
		"sfx":
			var n := str(e["name"])
			if n == "swing" and f != null and f.swing < 0.0: n = "dash"
			play(n)
		"shot":                     # Fighter.fire ~6196: one shot sound per 0.07 s for fast guns
			var w := sim.combat.wdata(str(e["key"]))
			var id := f.get_instance_id() if f else 0
			if float(w.get("cooldown", 1.0)) >= 0.1 or sim.combat.time - float(_shot_t.get(id, -1.0)) > 0.07:
				_shot_t[id] = sim.combat.time
				play(shot_name(w))
		"pad":                      # updatePads ~6382
			play("bounce")
		"crate":                    # spawnDrop ~6292
			play("drop")
		"crate_land":               # updatePickups ~6332
			play("clink")
		"crate_take":               # heal / power-up crate ~6352 (weapon crates come as "pickup")
			if f and f.is_player and sim.combat.wdata(str(e["crate"]["key"])).is_empty():
				play("pickup")
		"pickup":                   # Fighter.pickup ~5256/5270
			if f and f.is_player: play("pickup")
		"reload":                   # reload start: the mag-out sound (~5180); shotguns load shells (~5240)
			if f and f.is_player and f.slot >= 0 and f.slots[f.slot] != null:
				var rw := sim.combat.wdata(str(f.slots[f.slot]["key"]))
				play("shellIn" if rw.get("rtype", "") == "shell" else "mag")
		"respawn":                  # Combat.respawn: a cue for the player coming back in (bots respawn silently)
			if f and f.is_player: play("respawn", 0.8)

## The gun sound of Fighter.fire (~6196).
static func shot_name(w: Dictionary) -> String:
	if w.get("pellets", 0): return "shotgun"
	if w.get("big", false): return "mammoth"
	if w.get("name", "") == "Sniper": return "sniper"
	if w.get("style", "") == "punch": return "whack"
	return "shot"

func _on_setting(key: String, _value: Variant) -> void:
	if key == "volume" or key == "muted" or key == "sfx_volume":
		_apply_settings()

func _apply_settings() -> void:
	_muted = bool(Settings.get_value("muted", false))
	var vol := clampf(float(Settings.get_value("volume", 0.5)), 0.0, 1.0)
	var bus := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(vol, 0.0001)))
	AudioServer.set_bus_mute(bus, _muted or vol <= 0.0)
	var sb := AudioServer.get_bus_index(BUS)
	if sb >= 0:
		var sv := clampf(float(Settings.get_value("sfx_volume", 1.0)), 0.0, 1.0)
		AudioServer.set_bus_volume_db(sb, linear_to_db(maxf(sv, 0.0001)))
		AudioServer.set_bus_mute(sb, sv <= 0.0)
	if _muted: stop_all()

func stop_all() -> void:
	# Also called from a focus/resume notification, which can arrive before _ready() has built the pool: stop whatever
	# exists rather than indexing arrays that are still empty (or, before the resize, size 0).
	var n := mini(POOL, mini(_prio.size(), _pool.size()))
	for i in n:
		_prio[i] = 0
		_pool[i].stop()

## On quit: stop everything and, if a sound was playing up to now, give the mix thread time to drop the stopped
## playbacks (it frees them a few buffers later; quitting mid-sound would otherwise report the streams as leaked).
func _exit_tree() -> void:
	for p in _pool:
		p.stop()
		p.stream = null
	streams.clear()
	if Time.get_ticks_msec() < _busy_until + 200:
		OS.delay_msec(250)

## After an interruption (phone call, app in background, tab hidden): drop half-played sounds and re-apply the bus
## state. iOS (CoreAudio driver) reactivates its session by itself; the web build resumes its AudioContext on a user
## gesture, which is why the first touch/click/key also comes through here.
func resume() -> void:
	stop_all()
	_apply_settings()

func _input(e: InputEvent) -> void:
	if _unlocked: return
	if e is InputEventScreenTouch or e is InputEventMouseButton or e is InputEventKey or e is InputEventJoypadButton:
		if e.is_pressed():
			_unlocked = true
			resume()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		resume()
	elif what == NOTIFICATION_APPLICATION_PAUSED:
		stop_all()
