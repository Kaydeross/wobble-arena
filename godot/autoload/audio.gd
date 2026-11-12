extends Node
## Sound effects (autoload `Sfx`). Every recipe of the web game's synth (public/index.html `SFX`) is pre-rendered by
## tools/render-sfx.js into res://audio/sfx/<name>.wav (see docs/AUDIO.md). `Sfx.play(name, volume)` takes the next
## free player of a fixed pool (no allocation per call; the oldest sound is cut when all are busy).
## Settings: `volume` (0..1, the web game's settings.vol) on the Master bus, `muted` skips playback.

## Every name in the JS SFX table, in its order (tests check each one has a stream).
const NAMES: PackedStringArray = ["click", "pop", "whack", "clink", "slap", "swing", "shot", "shotgun", "flame",
	"mammoth", "sniper", "rocket", "boom", "wind", "kick", "boing", "bounce", "pickup", "drop", "mag", "shellIn"]
const DIR := "res://audio/sfx/"
const POOL := 12

var streams := {}                  ## name -> AudioStreamWAV
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _muted := false
var _shot_t := {}                  ## fighter instance id -> sim time of its last shot sound
var _busy_until := 0               ## ticks (ms) when the last started sound ends (see _exit_tree)
var _unlocked := false             ## a user gesture has happened (web audio needs one)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for n in NAMES:
		var s: AudioStream = load(DIR + n + ".wav")
		if s: streams[n] = s
		else: push_warning("Sfx: missing stream " + n)
	for i in POOL:
		var p := AudioStreamPlayer.new()
		p.name = "Sfx%d" % i
		add_child(p)
		_pool.append(p)
	_apply_settings()
	Settings.changed.connect(_on_setting)

## Plays one sound effect; `volume` scales it (linear, 1 = as rendered). Unknown names are ignored like the JS sfx().
func play(sfx_name: String, volume := 1.0) -> void:
	if _muted or volume <= 0.0: return
	var s: AudioStream = streams.get(sfx_name)
	if s == null: return
	var p := _free_player()
	p.stream = s
	p.volume_db = linear_to_db(volume)
	p.play()
	_busy_until = maxi(_busy_until, Time.get_ticks_msec() + int(s.get_length() * 1000.0))

## Combat/MatchSim/Pickups events -> sounds, at the points where the web game calls sfx() (World drains every event
## through here). Explicit "sfx" events already carry the JS name (topple boing, kick, kick/shove whack, melee swing,
## melee hitSfx, knife throw swing, knife clink).
func on_event(e: Dictionary, sim: MatchSim) -> void:
	var f: FighterState = e.get("f") if e.get("f") is FighterState else null
	match String(e["type"]):
		"sfx":
			play(str(e["name"]))
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

## The gun sound of Fighter.fire (~6196).
static func shot_name(w: Dictionary) -> String:
	if w.get("pellets", 0): return "shotgun"
	if w.get("big", false): return "mammoth"
	if w.get("name", "") == "Sniper": return "sniper"
	if w.get("style", "") == "punch": return "whack"
	return "shot"

## Next idle player, or the one that has been playing longest.
func _free_player() -> AudioStreamPlayer:
	for i in POOL:
		var p := _pool[(_next + i) % POOL]
		if not p.playing:
			_next = (_next + i + 1) % POOL
			return p
	var q := _pool[_next]
	_next = (_next + 1) % POOL
	return q

func _on_setting(key: String, _value: Variant) -> void:
	if key == "volume" or key == "muted":
		_apply_settings()

func _apply_settings() -> void:
	_muted = bool(Settings.get_value("muted", false))
	var vol := clampf(float(Settings.get_value("volume", 0.5)), 0.0, 1.0)
	var bus := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(vol, 0.0001)))
	AudioServer.set_bus_mute(bus, _muted or vol <= 0.0)
	if _muted: stop_all()

func stop_all() -> void:
	for p in _pool: p.stop()

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
