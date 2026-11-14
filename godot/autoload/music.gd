extends Node
## Background music (autoload `Music`): the web game's procedural score (public/index.html SoundManager.note),
## pre-rendered by tools/render-music.js into seamless 4-bar Ogg loops (res://audio/music, see docs/AUDIO.md).
##   menu        calm loop for the title and menus (88 bpm)
##   match_low   match, quiet moments                (118 bpm)
##   match_mid   match, fighting nearby              (127 bpm, 16th arps, hats and claps)
##   match_high  match, under pressure               (137.5 bpm, E-major turnaround, full drums)
## The mood follows the scene by itself: a world with a running match plays the match loops, the end of a match /
## the results panel settles into the calm menu loop (the results screen should never be silent) and anything else
## (title, menus, lobby) plays the menu loop. In a match the intensity is worked out like the web's musicTick (enemies
## close by, a recent hit, low health, someone one K.O. from the limit) and picks the tier, with hysteresis. Changes
## wait for the next bar line of the playing loop and crossfade, starting the new loop at the matching bar so the
## phrase carries on. Plays on the "Music" bus (Settings `music_volume`); `muted` (Master bus, autoload Sfx) silences
## it too. `duck(db, seconds)` dips the whole score under a big one-off moment (K.O., explosion).

const DIR := "res://audio/music/"
const TRACKS: PackedStringArray = ["menu", "match_low", "match_mid", "match_high"]
const BARS := 4
const BUS := "Music"
const XFADE := 0.35                ## crossfade between loops at a bar line (s)
const FADE_IN := 1.5
const FADE_OUT := 0.7
const SILENT_DB := -60.0
const DUCK_RELEASE := 0.12         ## the last part of a duck ramps back up instead of snapping (s)

var streams := {}                  ## track -> AudioStreamOggVorbis (loop on)
var mood := ""                     ## "" (silent) | "menu" | "match": what the scene asks for (the results screen is "menu")
var intensity := 0.0               ## 0..1, smoothed
var track := ""                    ## the loop playing now ("" = none)
var want := ""                     ## the loop to switch to on the next bar line
var auto := true                   ## follow the scene by itself (tests turn it off and call set_mood / set_intensity)
var duck_db := 0.0                 ## the duck requested right now (dB, <= 0): added on top of `music_volume`
var _duck_left := 0.0              ## seconds left in the current duck
var _duck_now := 0.0               ## the duck actually applied to the bus (ramps out over DUCK_RELEASE)
var _players: Array[AudioStreamPlayer] = []
var _cur := 0                      ## index of the active player in _players
var _target_i := 0.0               ## raw intensity before smoothing
var _tweens := [null, null]
var _headless := DisplayServer.get_name() == "headless"
var _busy_until := 0               ## ticks (ms) until which a stopped loop may still be held by the mixer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS          # keeps playing under the pause menu
	for n in TRACKS:
		var s: AudioStream = load(DIR + n + ".ogg")
		if s == null:
			push_warning("Music: missing loop " + n)
			continue
		if s is AudioStreamOggVorbis: (s as AudioStreamOggVorbis).loop = true
		streams[n] = s
	if AudioServer.get_bus_index(BUS) < 0:
		AudioServer.add_bus()
		var b := AudioServer.bus_count - 1
		AudioServer.set_bus_name(b, BUS)
		AudioServer.set_bus_send(b, "Master")
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = BUS
		p.name = "Music%d" % i
		p.volume_db = SILENT_DB
		add_child(p)
		_players.append(p)
	_apply_settings()
	Settings.changed.connect(_on_setting)

## "" stops the music, "menu" / "match" pick the loop family (the match tier comes from the intensity).
func set_mood(m: String) -> void:
	mood = m

## 0..1: how hot the match is (only used in the "match" mood).
func set_intensity(x: float) -> void:
	_target_i = clampf(x, 0.0, 1.0)

## Dip the whole score by `db` (negative, e.g. -6) for `seconds`, then ease back to the player's music volume. Called
## from the same moments as the heavy haptics (K.O., nearby explosion) so a big one-off sound reads clearly on top of
## the music while the track keeps playing (the results screen must not go quiet).
func duck(db := -6.0, seconds := 0.45) -> void:
	duck_db = clampf(db, -24.0, 0.0)
	_duck_left = maxf(0.05, seconds)
	_duck_now = duck_db              # instant dip: the big sound starts on this frame, not the next one
	_apply_settings()

## The loop the current mood and intensity call for. Tier thresholds have a gap (0.38 up / 0.30 down, 0.70 / 0.62)
## so the music doesn't flip back and forth around a boundary.
func pick_track() -> String:
	if mood == "menu": return "menu"
	if mood != "match": return ""
	var tier: int = TRACKS.find(track) - 1 if track.begins_with("match") else 0
	if tier <= 0: tier = 0 if intensity < 0.38 else (1 if intensity < 0.7 else 2)
	elif tier == 1: tier = 0 if intensity < 0.30 else (2 if intensity >= 0.7 else 1)
	else: tier = 2 if intensity >= 0.62 else (1 if intensity >= 0.30 else 0)
	return TRACKS[tier + 1]

func _process(delta: float) -> void:
	_update_duck(delta)
	if auto: _follow_scene()
	intensity += (_target_i - intensity) * minf(1.0, delta * 0.8)       # glides over a couple of seconds, like the web
	want = pick_track()
	if want == track: return
	var p := _players[_cur]
	if want == "":
		_fade(_cur, SILENT_DB, FADE_OUT, true)
		track = ""
		return
	if track == "" or not p.playing:
		_start(want, 0.0, FADE_IN)
		return
	var loop_len: float = (streams[track] as AudioStream).get_length() if streams.has(track) else 0.0
	if loop_len <= 0.0:
		_start(want, 0.0, XFADE)
		return
	var bar := loop_len / BARS
	var pos := p.get_playback_position() + AudioServer.get_time_since_last_mix()
	var into := fmod(pos, bar)
	if into < bar - maxf(delta * 1.5, 0.03) and into > 0.05: return       # wait for the bar line
	var next_bar := (int(floor(pos / bar)) + (1 if into > bar * 0.5 else 0)) % BARS
	var nlen: float = (streams[want] as AudioStream).get_length() if streams.has(want) else 0.0
	_start(want, next_bar * nlen / BARS, XFADE)

## Starts `trk` on the idle player at `from` seconds and crossfades over `fade` seconds.
func _start(trk: String, from: float, fade: float) -> void:
	if not streams.has(trk): return
	var old := _cur
	_cur = 1 - _cur
	var p := _players[_cur]
	p.stream = streams[trk]
	p.volume_db = SILENT_DB
	p.play(from)
	_fade(_cur, 0.0, fade, false)
	if _players[old].playing: _fade(old, SILENT_DB, fade, true)
	track = trk

## A mood change crossfades at the next bar line; the duck is a plain envelope on the Music bus, stepped every frame
## so it needs no tween and never fights a `music_volume` change.
func _update_duck(delta: float) -> void:
	var now := 0.0
	if _duck_left > 0.0:
		_duck_left = maxf(0.0, _duck_left - delta)
		now = duck_db * clampf(_duck_left / DUCK_RELEASE, 0.0, 1.0)
	if not is_equal_approx(now, _duck_now):
		_duck_now = now
		_apply_settings()

func _stopped(i: int) -> void:
	_players[i].stop()
	_busy_until = Time.get_ticks_msec()

func _fade(i: int, db: float, t: float, stop_after: bool) -> void:
	if _tweens[i] and (_tweens[i] as Tween).is_valid(): (_tweens[i] as Tween).kill()
	var p := _players[i]
	var tw := create_tween()
	tw.tween_property(p, "volume_db", db, maxf(t, 0.01))
	if stop_after: tw.tween_callback(_stopped.bind(i))
	_tweens[i] = tw

## Mood and intensity from the current scene: a world (it has a MatchSim in `sim`) plays the match; once the match is
## over or the results panel is up it settles into the calm menu loop (never silence) and everything else is the menu.
func _follow_scene() -> void:
	if _headless:                                   # test runs: no music unless a test drives it (auto = false)
		set_mood("")
		return
	var s := get_tree().current_scene
	if s == null:
		set_mood("menu")
		return
	var sim: Variant = s.get("sim")
	if not (sim is MatchSim):
		set_mood("menu")
		return
	var m: MatchSim = sim
	if m.combat.rules == null or m.combat.rules.match_over or s.get("_results") != null:
		set_mood("menu")                            # the results screen keeps a results-friendly loop going
		return
	set_mood("match")
	set_intensity(match_intensity(m))

## The web's musicTick: 0.2 base, +0.13 per enemy within 14 m (max +0.4), +0.2 for 3 s after a hit, +0.15 under 35 %
## health, +0.15 when someone is one K.O. from the limit.
static func match_intensity(m: MatchSim) -> float:
	var me: FighterState = m.player
	if me == null: return 0.1
	var c: Combat = m.combat
	var i := 0.2
	var near := 0
	for f: FighterState in m.fighters:
		if f == me or f.dead or c.is_friend(f, me): continue
		var dx := f.phys.px - me.phys.px
		var dz := f.phys.pz - me.phys.pz
		if dx * dx + dz * dz < 196.0: near += 1
	i += minf(0.4, near * 0.13)
	if c.time - me.last_hit_time < 3.0: i += 0.2
	if not me.dead and me.hp < c.max_hp(me) * 0.35: i += 0.15
	if c.rules and c.rules.limit > 0:
		for f: FighterState in m.fighters:
			if f.ko >= c.rules.limit - 1:
				i += 0.15
				break
	return clampf(i, 0.0, 1.0)

func _on_setting(key: String, _value: Variant) -> void:
	if key == "music_volume": _apply_settings()

func _apply_settings() -> void:
	var b := AudioServer.get_bus_index(BUS)
	if b < 0: return
	var v := clampf(float(Settings.get_value("music_volume", 0.5)), 0.0, 1.0)
	AudioServer.set_bus_volume_db(b, linear_to_db(maxf(v, 0.0001)) + _duck_now)
	AudioServer.set_bus_mute(b, v <= 0.0)

func stop_all() -> void:
	for i in _players.size():
		if _tweens[i] and (_tweens[i] as Tween).is_valid(): (_tweens[i] as Tween).kill()
		_tweens[i] = null
		if _players[i].playing: _busy_until = Time.get_ticks_msec()
		_players[i].stop()
	track = ""

## Phone call / app in the background: pause the loop where it is and carry on from there on return.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		for p in _players: p.stream_paused = true
	elif what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		for p in _players: p.stream_paused = false

## On quit: stop, drop the streams and, if a loop was playing, give the mix thread time to free its playback (as
## Sfx does), so the streams are not reported as leaked.
func _exit_tree() -> void:
	stop_all()
	for p in _players: p.stream = null
	streams.clear()
	if _busy_until > 0 and Time.get_ticks_msec() < _busy_until + 200:
		OS.delay_msec(250)
