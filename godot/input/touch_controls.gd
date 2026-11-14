class_name TouchControls
extends Control
## On-screen touch controls (first ported from the web game's touch layer, public/index.html ~9154-9247), redesigned for
## phones: a floating move stick on the left, drag anywhere else to look, and at most four action buttons in an arc
## around the right thumb (mirrored in left-handed mode). Writes into the shared InputState (source "touch").
##
##   FIRE    big yellow, held. Drag while holding to aim the camera. An empty magazine reloads by itself on FIRE.
##           Shows a yellow ring + scope badge while the scope (aim) is on.
##   JUMP    teal, held.
##   MELEE   tap = shove; hold (HOLD_KICK s) or flick (FLICK px) = kick. A ring fills while held, the icon turns into a boot.
##   context only while it applies: DASH (ninja weapon in hand, with charge pips), else RECOVER when knocked into the air (the "boing
##           burst", logic/skills.gd; a ring shows the charge coming back), else RELOAD (gun with a magazine and spare
##           ammo; shows the reload progress).
##   AIM     double-tap the look area to toggle the scope (tap again twice to leave it).
##   weapons tap a hotbar slot to equip it (the Spatula slot is the quick melee, like Q); tap the slot already in hand to
##           swap back to the last weapon; swipe sideways across the hotbar to cycle.
##   pause   the button at the top corner.
##   spectate `spectate_mode` (the player is out, World spectates): only the pause button; any other tap emits
##           spectate_tap (World follows the next fighter).
## Drawn with vector icons (_draw, no fonts). Layout respects left-handed mode, button scale, opacity and safe areas.
## World wires `state`; the HUD calls attach(sim, hotbar) so the context button and hotbar taps can read the match.

signal pause_pressed
signal spectate_tap

## CSS px of the web layout -> canvas units. The web layout is sized for ~390pt-tall phone screens, our canvas is 540 tall.
const UNIT := 1.35
const LOOK_K := 0.0052        ## rad per CSS px (web: 0.0052 * sens)
const STICK_R := 54.0
const MOVE_W := 0.45
const MOVE_TOP := 0.14
const HOLD_KICK := 0.28       ## s holding MELEE before it kicks
const FLICK := 26.0           ## canvas units dragged on MELEE that count as a flick (kick)
const DOUBLE_TAP_MS := 320
const TAP_MOVE := 16.0        ## canvas units a tap may drift
const HOTBAR_SWIPE := 44.0    ## canvas units sideways on the hotbar that cycle weapons
## id, label, action, size, distance from the thumb-side edge, distance from the bottom, held (else tap).
## An arc around FIRE: JUMP to its inner side, MELEE above it, the contextual button between them.
const BUTTONS := [
	["fire", "FIRE", "fire", 96, 22, 22, true],
	["jump", "JUMP", "jump", 68, 132, 16, true],
	["melee", "MELEE", "shove", 58, 34, 134, false],
	["context", "", "", 52, 124, 104, false],
]
const PAUSE_SIZE := 46.0     ## x UNIT = 62 canvas px: 45 pt at the UI scale (ui/ui_scale.gd)

var state: InputState
var sim: MatchSim
var hotbar: Control            ## ui/hud_hotbar.gd (slot taps)
var lefty := false
var scale_k := 1.0
var opacity := 0.85
## Spectator mode: no controls, a tap anywhere but pause = spectate_tap. Set by World.spectate().
var spectate_mode := false:
	set(v):
		if v == spectate_mode: return
		spectate_mode = v
		if v: release_all()
		queue_redraw()

var _touch := {}               ## touch index -> "move" | "look" | "pause" | "hotbar" | button id
var _last := {}                ## touch index -> last position (look / fire drag)
var _stick_origin := Vector2.ZERO
var _stick_pos := Vector2.ZERO
var _down := {}                ## button id -> true while pressed
var _insets := [0.0, 0.0, 0.0, 0.0]   ## left, top, right, bottom safe-area insets in canvas units
var _anim := {}                ## button id -> press animation 0..1 (visual only)
var _melee := {"t": 0.0, "p0": Vector2.ZERO, "kicked": false}
var _look0 := {}               ## touch index -> [start position, start msec, moved]
var _look_tap := [-100000, Vector2.ZERO]   ## last quick tap on the look area: [msec, position]
var _hb := {"i": -1, "p0": Vector2.ZERO}   ## hotbar touch: slot under the finger, start position
var _flash_slot := -1         ## hotbar slot flashing after a tap (visual only)
var _prev_slot := -1           ## hotbar slot in hand before the last slot tap (swap back)
var _ctx := ""                 ## "dash" | "recover" | "reload" | "" (hidden)
var _ctx_sig := ""

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_settings()
	Settings.changed.connect(func(_k, _v): _load_settings())
	get_viewport().size_changed.connect(_update_insets)
	_update_insets()
	visible = wanted()

static func wanted() -> bool:
	var mode := str(Settings.get_value("touch_mode", "auto"))
	return mode == "on" or (mode == "auto" and Tier.touch_default())

## The match (context button) and the HUD hotbar (slot taps). Called by MatchHud.bind().
func attach(s: MatchSim, hb: Control) -> void:
	sim = s
	hotbar = hb
	_prev_slot = -1
	_refresh_context()

func _load_settings() -> void:
	lefty = bool(Settings.get_value("touch_lefty", false))
	scale_k = float(Settings.get_value("touch_scale", 1.0))
	opacity = float(Settings.get_value("touch_opacity", 0.85))
	queue_redraw()

## Safe-area insets (notch, home indicator) from DisplayServer, converted to canvas units. Phones only:
## on desktop the "safe area" is the screen minus the dock, which says nothing about our window.
func _update_insets() -> void:
	_insets = SafeArea.insets(get_viewport())
	queue_redraw()

func safe_insets() -> Array:
	return _insets

## Button centre and radius in canvas units.
func button_rect(b: Array) -> Array:
	var vs := get_viewport_rect().size
	var u := UNIT * scale_k
	var sz: float = float(b[3]) * u
	var x: float = float(b[4]) * u
	var y: float = float(b[5]) * u
	var cy: float = vs.y - _insets[3] - y - sz / 2.0
	var cx: float = (_insets[0] + x + sz / 2.0) if lefty else (vs.x - _insets[2] - x - sz / 2.0)
	return [Vector2(cx, cy), sz / 2.0]

func button(id: String) -> Array:
	for b in BUTTONS:
		if b[0] == id:
			return b
	return []

func pause_rect() -> Rect2:
	var vs := get_viewport_rect().size
	var s := PAUSE_SIZE * UNIT
	var top: float = 6.0 * UNIT + _insets[1]
	var x: float = (8.0 * UNIT + _insets[0]) if lefty else (vs.x - 8.0 * UNIT - _insets[2] - s)
	return Rect2(x, top, s, s)

## What the contextual button does right now: "dash", "recover", "reload" or "" (hidden).
func context_action() -> String:
	return _ctx

## Buttons drawn and touchable right now (FIRE, JUMP, MELEE and the context button when it applies).
func visible_buttons() -> Array:
	var out := []
	for b in BUTTONS:
		if b[0] != "context" or _ctx != "":
			out.append(b[0])
	return out

func _in_move_zone(p: Vector2) -> bool:
	var vs := get_viewport_rect().size
	if p.y < vs.y * MOVE_TOP:
		return false
	return p.x > vs.x * (1.0 - MOVE_W) if lefty else p.x < vs.x * MOVE_W

func _input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if not visible and str(Settings.get_value("touch_mode", "auto")) == "auto":
			visible = true   # a touch screen on a laptop or in a browser: show the controls once it is used
		if not visible or state == null:
			return
		if e.canceled:
			# The OS took the touch away (Control Centre, a notification, a gesture): drop it without tap actions.
			_drop_touch(e.index)
			get_viewport().set_input_as_handled()
			return
		var p: Vector2 = (make_input_local(e) as InputEventScreenTouch).position
		if spectate_mode:
			if e.pressed:
				if pause_rect().grow(6).has_point(p): _touch_down(e.index, p)
				else: spectate_tap.emit()
			get_viewport().set_input_as_handled()
			return
		if e.pressed:
			_touch_down(e.index, p)
		else:
			_touch_up(e.index, p)
		get_viewport().set_input_as_handled()
	elif e is InputEventScreenDrag and visible and state != null and _touch.has(e.index):
		_touch_move(e.index, (make_input_local(e) as InputEventScreenDrag).position)
		get_viewport().set_input_as_handled()

# ---------------- hotbar slots ----------------

## Hotbar slot rect (0..3, 3 = Spatula) in this control's coordinates, or an empty Rect2 when there is no hotbar.
func hotbar_slot_rect(i: int) -> Rect2:
	if hotbar == null or not is_instance_valid(hotbar) or not hotbar.is_visible_in_tree() or not hotbar.has_method("slot_rect"):
		return Rect2()
	var xf := get_global_transform_with_canvas().affine_inverse() * hotbar.get_global_transform_with_canvas()
	return xf * (hotbar.slot_rect(i) as Rect2)

func _hotbar_slot_at(p: Vector2) -> int:
	for i in 4:
		var r := hotbar_slot_rect(i)
		if r.size.x > 0.0 and r.grow(4.0).has_point(p):
			return i
	return -1

func _active_slot() -> int:
	if hotbar == null or not is_instance_valid(hotbar):
		return -1
	var sl: Array = hotbar.get("slots")
	for i in sl.size():
		if sl[i].get("active", false):
			return i
	return -1

func _slot_filled(i: int) -> bool:
	var sl: Array = hotbar.get("slots") if hotbar else []
	return i >= 0 and i < sl.size() and not sl[i].get("empty", true)

## Tap on hotbar slot i: equip it (Spatula = quick melee); on the slot in hand, swap back to the previous one.
func _hotbar_tap(i: int) -> void:
	var cur := _active_slot()
	var go := i
	if i == cur and i != 3:
		if not _slot_filled(_prev_slot) or _prev_slot == cur:
			return
		go = _prev_slot
	if not _slot_filled(go):
		return
	if go == 3:
		state.press("spatula")
		return
	if cur >= 0 and cur != 3:
		_prev_slot = cur
	state.press("slot%d" % (go + 1))

# ---------------- touches ----------------

func _touch_down(i: int, p: Vector2) -> void:
	# iOS recycles finger indices: a new down on an index that is still marked down must not orphan what that finger
	# held before (a dropped FIRE release). Drop the old role first, without firing its tap actions.
	_drop_touch(i)
	if pause_rect().grow(6).has_point(p):
		_touch[i] = "pause"
		_anim["pause"] = 1.0
		queue_redraw()
		pause_pressed.emit()
		return
	for b in BUTTONS:
		var id: String = b[0]
		if id == "context" and _ctx == "":
			continue
		var r := button_rect(b)
		if p.distance_to(r[0]) <= r[1] + 4.0:
			if _down.has(id):
				# Another finger already holds this button (e.g. a FIRE release that never arrived). Take the button
				# over instead of ignoring the press, so releasing this finger clears it.
				_disown(id, i)
				_touch[i] = id; _last[i] = p
				match id:
					"melee":
						_melee = {"t": 0.0, "p0": p, "kicked": false}   # restart the hold timer
					"context":
						pass   # the other finger already fired the tap; do not fire it twice
					_:
						state.hold("touch", b[2], true)                 # stays held
				queue_redraw()
				return
			_touch[i] = id; _last[i] = p; _down[id] = true
			match id:
				"melee":
					_melee = {"t": 0.0, "p0": p, "kicked": false}
				"context":
					if (_ctx == "reload" and sim and sim.player.reloading) or (_ctx == "recover" and sim and Skills.recover_n(sim.player) <= 0):
						pass
					else:
						state.press(_ctx)
				_:
					state.hold("touch", b[2], true)
			queue_redraw()
			return
	var hs := _hotbar_slot_at(p)
	if hs >= 0 and not _touch.values().has("hotbar"):
		_touch[i] = "hotbar"
		_hb = {"i": hs, "p0": p}
		_flash_slot = hs
		_anim["slot"] = 1.0
		return
	if _in_move_zone(p) and not _touch.values().has("move"):
		_touch[i] = "move"
		_stick_origin = p; _stick_pos = p
		_update_stick()
	elif not _touch.values().has("look"):
		_touch[i] = "look"; _last[i] = p
		var now := Time.get_ticks_msec()
		if now - int(_look_tap[0]) <= DOUBLE_TAP_MS and p.distance_to(_look_tap[1]) < 70.0:
			state.aim_toggle = not state.aim_toggle   # double-tap the look area: scope on / off
			_look_tap[0] = -100000
			now = -100000                            # this touch cannot start another double-tap
		_look0[i] = [p, now, 0.0]
	queue_redraw()

func _touch_move(i: int, p: Vector2) -> void:
	var what: String = _touch[i]
	if what == "move":
		var r := STICK_R * UNIT * scale_k
		var d := p - _stick_origin
		if d.length() > r:   # the base follows the thumb when dragged past its edge
			_stick_origin += d * ((d.length() - r) / d.length())
		_stick_pos = p
		_update_stick()
	elif what == "look" or what == "fire":   # hold FIRE and drag to aim
		_look(p - _last[i])
		_last[i] = p
		if _look0.has(i):
			_look0[i][2] = maxf(_look0[i][2], p.distance_to(_look0[i][0]))
	elif what == "melee":
		if not _melee["kicked"] and p.distance_to(_melee["p0"]) > FLICK:
			_kick()
	elif what == "hotbar":
		_last[i] = p
	queue_redraw()

func _touch_up(i: int, p: Vector2 = Vector2.INF) -> void:
	if not _touch.has(i):
		return
	var what: String = _touch[i]
	var lp: Vector2 = _last.get(i, p)
	if p == Vector2.INF: p = lp
	_touch.erase(i); _last.erase(i)
	if what == "move":
		state.set_move("touch", Vector2.ZERO)
		state.hold("touch", "sprint", false)
	elif what == "look":
		var l0: Array = _look0.get(i, [])
		_look0.erase(i)
		if l0.size() == 3 and int(l0[1]) >= 0 and l0[2] < TAP_MOVE and p.distance_to(l0[0]) < TAP_MOVE and Time.get_ticks_msec() - int(l0[1]) < 260:
			_look_tap = [Time.get_ticks_msec(), l0[0]]
	elif what == "hotbar":
		var dx: float = p.x - (_hb["p0"] as Vector2).x
		if absf(dx) > HOTBAR_SWIPE:
			state.press("swap")              # swipe across the hotbar: next weapon
		elif p.distance_to(_hb["p0"]) < 30.0:
			_hotbar_tap(int(_hb["i"]))
		_hb = {"i": -1, "p0": Vector2.ZERO}
	elif _down.has(what):
		_down.erase(what)
		if what == "melee":
			if not _melee["kicked"]:
				state.press("shove")         # a quick tap shoves
		else:
			var b := button(what)
			if not b.is_empty() and b[6]:
				state.hold("touch", b[2], false)
	queue_redraw()

## Drop one finger's role without emitting any tap action (index reused, touch cancelled, focus lost). A held MELEE
## that has not kicked yet is dropped, not shoved.
func _drop_touch(i: int) -> void:
	if not _touch.has(i):
		return
	var what: String = _touch[i]
	_touch.erase(i); _last.erase(i); _look0.erase(i)
	match what:
		"move":
			state.set_move("touch", Vector2.ZERO)
			state.hold("touch", "sprint", false)
		"hotbar":
			_hb = {"i": -1, "p0": Vector2.ZERO}
		"pause":
			pass
		_:
			if _down.has(what):
				_down.erase(what)
				if what == "melee":
					_melee = {"t": 0.0, "p0": Vector2.ZERO, "kicked": true}
				var b := button(what)
				if not b.is_empty() and b[6]:
					state.hold("touch", b[2], false)
	queue_redraw()

## A new finger takes button `id` over: the other fingers' claims on it are dropped, so their later release does not
## clear the action the new owner still holds.
func _disown(id: String, keep: int) -> void:
	for i in _touch.keys():
		if i != keep and _touch[i] == id:
			_touch.erase(i)
			_last.erase(i)
			_look0.erase(i)

func _kick() -> void:
	_melee["kicked"] = true
	state.press("kick")
	_anim["kick"] = 1.0
	queue_redraw()

func _update_stick() -> void:
	var r := STICK_R * UNIT * scale_k
	var d := (_stick_pos - _stick_origin) / r
	var v := Vector2(d.x, -d.y).limit_length(1.0)   # x = right, y = forward
	state.set_move("touch", v)
	state.hold("touch", "sprint", v.length() > 0.93 and v.y > 0.3)   # push to the edge to sprint

func _look(d: Vector2) -> void:
	var k := LOOK_K * float(Settings.get_value("sens", 1.0)) / UNIT
	var inv := -1.0 if bool(Settings.get_value("invert_y", false)) else 1.0
	state.add_look(-d.x * k, -d.y * k * inv)

## A finger is on the look area (or dragging from FIRE): the follow camera does not auto-centre meanwhile.
func look_held() -> bool:
	return _touch.values().has("look") or _touch.values().has("fire")

## Let go of every touch (pause, leaving the match, focus lost). A held MELEE that has not kicked yet is dropped, not shoved.
func release_all() -> void:
	_melee["kicked"] = true
	for i in _touch.keys():
		_touch_up(i)
	if state != null:
		for id in _down.keys():   # a held button whose touch entry was lost must not stay held either
			var b := button(id)
			if not b.is_empty() and b[6]:
				state.hold("touch", b[2], false)
		state.set_move("touch", Vector2.ZERO)
		state.hold("touch", "sprint", false)
		state.aim_toggle = false
	_touch.clear(); _down.clear(); _look0.clear(); _last.clear()

## Focus loss / backgrounding takes the touches away without a release event (Control Centre, a notification banner,
## the app switcher). Let go of everything so a held FIRE cannot keep firing when the app comes back.
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED:
			if state != null:
				release_all()

# ---------------- per frame ----------------

func _refresh_context() -> void:
	var id := ""
	var sig := ""
	if sim != null and sim.player != null and not sim.player.dead:
		var p := sim.player
		if sim.combat.rules.dash_gear(p):
			id = "dash"
			sig = "dash%d" % p.dash_n
		elif Skills.recover_offer(p, sim):
			id = "recover"
			sig = "recover%d" % int(Skills.recover_ready_k(p) * 30.0)
		else:
			var s: Variant = p.current_slot()
			var w := sim.combat.wdata(p.weapon) if p.weapon != "" else {}
			if s != null and w.get("type", "") == "gun" and w.get("mag", 0) and int(s["mag"]) >= 0 and not sim.combat.inf \
					and (p.reloading or int(s["ammo"]) > 0):
				id = "reload"
				sig = "reload%d" % (int(p.rl_t / p.rl_dur * 30.0) if p.reloading and p.rl_dur > 0.0 else -1)
	_ctx = id
	if sig != _ctx_sig:
		_ctx_sig = sig
		queue_redraw()

func _process(dt: float) -> void:
	_refresh_context()
	# Fail-safe: every held button must have a finger on it. A release the OS never delivered (or a lost touch
	# record) would otherwise leave FIRE held forever; release it instead of firing on.
	if state != null and not _down.is_empty():
		var roles := _touch.values()
		for id in _down.keys():
			if roles.has(id):
				continue
			_down.erase(id)
			if id == "melee":
				_melee = {"t": 0.0, "p0": Vector2.ZERO, "kicked": true}   # an orphaned MELEE is dropped, not shoved
			else:
				var b := button(id)
				if not b.is_empty() and b[6]:
					state.hold("touch", b[2], false)
		queue_redraw()
	if _down.has("melee") and not _melee["kicked"]:
		_melee["t"] += dt
		if _melee["t"] >= HOLD_KICK:
			_kick()
		queue_redraw()
	# press animation: each button eases toward 1 while held (fast in, slower springy out)
	var busy := false
	for b in BUTTONS:
		var id: String = b[0]
		var on: bool = _down.has(id)
		var a: float = _anim.get(id, 0.0)
		var t := 1.0 if on else 0.0
		if absf(a - t) > 0.001:
			a = move_toward(a, t, dt * (16.0 if on else 7.0))
			_anim[id] = a
			busy = true
	var cv: float = _anim.get("ctx_vis", 0.0)
	var ct := 1.0 if _ctx != "" else 0.0
	if absf(cv - ct) > 0.001:
		_anim["ctx_vis"] = move_toward(cv, ct, dt * 6.0)
		busy = true
	for k in ["pause", "kick", "slot"]:
		var pa: float = _anim.get(k, 0.0)
		if pa > 0.0:
			_anim[k] = move_toward(pa, 0.0, dt * 5.0)
			busy = true
	if busy:
		queue_redraw()

# ---------------- drawing ----------------

## Opacity tier: FIRE and JUMP strongest, MELEE next, the contextual button lightest.
static func tier_alpha(id: String) -> float:
	match id:
		"fire", "jump": return 1.0
		"melee": return 0.9
	return 0.86

func _draw() -> void:
	var ink := UiTheme.INK
	var yel := UiTheme.ACCENT
	var aiming := state != null and state.aim_toggle
	for b in ([] if spectate_mode else BUTTONS):
		var id: String = b[0]
		var vis := 1.0
		if id == "context":
			vis = _anim.get("ctx_vis", 0.0)
			if _ctx == "" and vis <= 0.01:
				continue
		var r := button_rect(b)
		var a: float = _anim.get(id, 0.0)
		var op := opacity * tier_alpha(id) * vis
		var c: Vector2 = r[0]
		var rad: float = r[1] * (1.0 - 0.1 * a) * (0.7 + 0.3 * vis)
		var fill: Color
		var icon_c := Color(1, 1, 1, op)
		match id:
			"fire":
				fill = Color(yel.r, yel.g, yel.b, 0.9 * op); icon_c = Color(ink.r, ink.g, ink.b, op)
			"jump":
				fill = Color(0.08, 0.31, 0.36, 0.9 * op)
			_:
				fill = Color(ink.r, ink.g, ink.b, 0.76 * op)
		fill = fill.lerp(Color(1, 1, 1, fill.a), 0.3 * a)        # brighter while pressed
		draw_circle(c + Vector2(0, 3.0 * (1.0 - a)), rad, Color(0, 0, 0, 0.22 * op))   # soft drop shadow
		if a > 0.01:
			draw_circle(c, rad + 6.0 * a, Color(yel.r, yel.g, yel.b, 0.25 * a * op))  # press glow
		draw_circle(c, rad, fill)
		draw_arc(c + Vector2(0, -rad * 0.08), rad * 0.82, PI * 1.15, PI * 1.85, 24, Color(1, 1, 1, 0.16 * op), rad * 0.12, true)   # top sheen
		var edge := Color(ink.r, ink.g, ink.b, 0.76 * op) if id == "fire" else Color(1, 1, 1, 0.78 * op)
		draw_arc(c, rad - 1.0, 0, TAU, 48, edge, 3.5, true)
		match id:
			"fire":
				_icon("fire", c, rad * 0.5, icon_c)
				if aiming:   # scope on: a yellow ring and a scope badge on FIRE's inner shoulder
					draw_arc(c, rad + 7.0, 0, TAU, 56, Color(yel.r, yel.g, yel.b, 0.95 * opacity), 4.0, true)
					var bc := c + Vector2.from_angle(PI * (1.25 if not lefty else 1.75)) * (rad + 4.0)
					draw_circle(bc, rad * 0.3, Color(ink.r, ink.g, ink.b, 0.9 * opacity))
					draw_arc(bc, rad * 0.3, 0, TAU, 28, Color(yel.r, yel.g, yel.b, opacity), 2.0, true)
					_icon("aim", bc, rad * 0.17, Color(yel.r, yel.g, yel.b, opacity))
			"melee":
				var kicked: bool = _down.has("melee") and _melee["kicked"]
				var ka: float = _anim.get("kick", 0.0)
				_icon("kick" if kicked or ka > 0.4 else "shove", c, rad * 0.52, icon_c)
				if _down.has("melee") and not kicked:   # hold progress toward the kick
					var k := clampf(_melee["t"] / HOLD_KICK, 0.0, 1.0)
					draw_arc(c, rad + 4.0, -PI / 2.0, -PI / 2.0 + TAU * k, 40, Color(yel.r, yel.g, yel.b, 0.9 * opacity), 4.0, true)
				else:   # a small boot on the rim: hold for a kick
					var bc := c + Vector2.from_angle(PI * (1.75 if not lefty else 1.25)) * rad * 0.92
					draw_circle(bc, rad * 0.32, Color(ink.r, ink.g, ink.b, 0.85 * op))
					draw_arc(bc, rad * 0.32, 0, TAU, 24, Color(1, 1, 1, 0.5 * op), 1.5, true)
					_icon("kick", bc, rad * 0.17, Color(1, 1, 1, 0.9 * op))
			"context":
				var cid := _ctx if _ctx != "" else ("dash" if _ctx_sig.begins_with("dash") else ("recover" if _ctx_sig.begins_with("recover") else "reload"))
				var p: FighterState = sim.player if sim else null
				var rk := Skills.recover_ready_k(p) if p != null and cid == "recover" else 1.0
				if cid == "recover" and rk < 1.0:   # charge used: dim icon + a ring filling back up
					_icon("recover", c, rad * 0.5, Color(1, 1, 1, 0.4 * op))
					draw_arc(c, rad + 3.0, -PI / 2.0, -PI / 2.0 + TAU * rk, 40, Color(yel.r, yel.g, yel.b, 0.95 * op), 4.0, true)
				elif cid == "reload" and p != null and p.reloading and p.rl_dur > 0.0:
					_icon("reload", c, rad * 0.5, Color(1, 1, 1, 0.45 * op))
					draw_arc(c, rad + 3.0, -PI / 2.0, -PI / 2.0 + TAU * clampf(p.rl_t / p.rl_dur, 0.0, 1.0), 40, Color(yel.r, yel.g, yel.b, 0.95 * op), 4.0, true)
				else:
					_icon(cid, c + (Vector2(0, -rad * 0.12) if cid == "dash" else Vector2.ZERO), rad * 0.5, icon_c)
				if cid == "dash" and p != null:   # charge pips
					for k in 3:
						var pc := c + Vector2((k - 1) * rad * 0.32, rad * 0.58)
						draw_circle(pc, rad * 0.1, Color(yel.r, yel.g, yel.b, op) if k < p.dash_n else Color(1, 1, 1, 0.25 * op))
			_:
				_icon(id, c, rad * 0.5, icon_c)
	# a light flash on the tapped hotbar slot
	var sa: float = _anim.get("slot", 0.0)
	if sa > 0.0 and _flash_slot >= 0:
		var sr := hotbar_slot_rect(_flash_slot)
		if sr.size.x > 0.0:
			var fb := UiTheme.box(Color(1, 1, 1, 0.18 * sa), 14, Color(yel.r, yel.g, yel.b, 0.8 * sa), 2, 0)
			draw_style_box(fb, sr)
	# pause
	var pr := pause_rect()
	var pa: float = _anim.get("pause", 0.0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(ink.r, ink.g, ink.b, 0.62 * opacity).lerp(Color(1, 1, 1, 0.6 * opacity), 0.3 * pa)
	sb.border_color = Color(1, 1, 1, 0.55 * opacity)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(int(14 * UNIT))
	sb.shadow_color = Color(0, 0, 0, 0.2 * opacity); sb.shadow_size = 4; sb.shadow_offset = Vector2(0, 2)
	sb.anti_aliasing = true
	draw_style_box(sb, pr.grow(-3.0 * pa))
	_icon("pause", pr.get_center(), pr.size.x * 0.24, Color(1, 1, 1, opacity))
	if spectate_mode: return
	# floating stick: a faint ghost where the thumb usually rests, the real ring + knob while held
	var sr := STICK_R * UNIT * scale_k
	var kr := 23.0 * UNIT * scale_k
	if _touch.values().has("move"):
		var v := _stick_pos - _stick_origin
		var sprint := state != null and state.is_held("sprint")
		draw_circle(_stick_origin, sr, Color(ink.r, ink.g, ink.b, 0.4 * opacity))
		draw_arc(_stick_origin, sr, 0, TAU, 56, Color(yel.r, yel.g, yel.b, 0.9 * opacity) if sprint else Color(1, 1, 1, 0.5 * opacity), 3.0, true)
		draw_arc(_stick_origin, sr * 0.55, 0, TAU, 40, Color(1, 1, 1, 0.12 * opacity), 1.5, true)
		if v.length() > 4.0:   # highlight the rim in the push direction
			var ang := v.angle()
			draw_arc(_stick_origin, sr - 4.0, ang - 0.5, ang + 0.5, 16, Color(yel.r, yel.g, yel.b, 0.85 * opacity), 5.0, true)
		var knob := _stick_origin + v.limit_length(sr)
		draw_circle(knob + Vector2(0, 3), kr, Color(0, 0, 0, 0.25 * opacity))
		draw_circle(knob, kr, Color(1, 1, 1, 0.85 * opacity))
		draw_arc(knob, kr - 1.0, 0, TAU, 32, Color(ink.r, ink.g, ink.b, 0.35 * opacity), 2.0, true)
		draw_circle(knob, kr * 0.45, Color(ink.r, ink.g, ink.b, 0.12 * opacity))
	else:
		var gp := stick_home()
		draw_circle(gp, sr, Color(ink.r, ink.g, ink.b, 0.16 * opacity))
		draw_arc(gp, sr, 0, TAU, 56, Color(1, 1, 1, 0.22 * opacity), 2.0, true)
		draw_circle(gp, kr, Color(1, 1, 1, 0.18 * opacity))

## Where the faint stick ghost sits (lower part of the move zone, inside the safe area).
func stick_home() -> Vector2:
	var vs := get_viewport_rect().size
	var sr := STICK_R * UNIT * scale_k
	var y: float = vs.y - _insets[3] - sr - 34.0 * UNIT
	var x: float = _insets[0] + sr + 40.0 * UNIT
	if lefty: x = vs.x - _insets[2] - sr - 40.0 * UNIT
	return Vector2(x, y)

# ---------- vector icons (no fonts / emoji): `s` = half the icon size ----------

func _cap(a: Vector2, b: Vector2, w: float, col: Color) -> void:
	draw_line(a, b, col, w, true)
	draw_circle(a, w / 2.0, col)
	draw_circle(b, w / 2.0, col)

func _icon(id: String, c: Vector2, s: float, col: Color) -> void:
	var w := maxf(2.0, s * 0.26)
	match id:
		"fire":   # bullet burst: a spiky star with a hole
			var pts := PackedVector2Array()
			for i in 16:
				var ang := -PI / 2.0 + i * TAU / 16.0
				pts.append(c + Vector2.from_angle(ang) * (s * (1.0 if i % 2 == 0 else 0.55)))
			draw_colored_polygon(pts, col)
			draw_circle(c, s * 0.28, Color(UiTheme.ACCENT.r, UiTheme.ACCENT.g, UiTheme.ACCENT.b, col.a))
		"jump":   # up arrow over a ground line
			_cap(c + Vector2(0, s * 0.55), c + Vector2(0, -s * 0.55), w, col)
			_cap(c + Vector2(0, -s * 0.75), c + Vector2(-s * 0.6, -s * 0.1), w, col)
			_cap(c + Vector2(0, -s * 0.75), c + Vector2(s * 0.6, -s * 0.1), w, col)
			_cap(c + Vector2(-s * 0.7, s * 0.95), c + Vector2(s * 0.7, s * 0.95), w * 0.8, col)
		"aim":    # scope reticle
			draw_arc(c, s * 0.75, 0, TAU, 32, col, w * 0.8, true)
			_cap(c + Vector2(0, -s * 1.05), c + Vector2(0, -s * 0.35), w * 0.7, col)
			_cap(c + Vector2(0, s * 1.05), c + Vector2(0, s * 0.35), w * 0.7, col)
			_cap(c + Vector2(-s * 1.05, 0), c + Vector2(-s * 0.35, 0), w * 0.7, col)
			_cap(c + Vector2(s * 1.05, 0), c + Vector2(s * 0.35, 0), w * 0.7, col)
			draw_circle(c, w * 0.45, col)
		"reload": # circular arrow
			draw_arc(c, s * 0.7, -PI * 0.35, PI * 1.35, 28, col, w * 0.85, true)
			var tip := c + Vector2.from_angle(-PI * 0.35) * s * 0.7
			draw_colored_polygon(PackedVector2Array([tip + Vector2(-s * 0.05, -s * 0.5), tip + Vector2(s * 0.5, s * 0.08), tip + Vector2(-s * 0.35, s * 0.3)]), col)
		"shove":  # open palm
			var palm := Rect2(c + Vector2(-s * 0.55, -s * 0.1), Vector2(s * 1.1, s * 0.85))
			var sb := StyleBoxFlat.new()
			sb.bg_color = col
			sb.set_corner_radius_all(int(s * 0.3))
			sb.anti_aliasing = true
			draw_style_box(sb, palm)
			for i in 4:
				var x := palm.position.x + s * 0.14 + i * s * 0.27
				_cap(Vector2(x, palm.position.y + s * 0.1), Vector2(x, palm.position.y - s * (0.6 if i == 1 or i == 2 else 0.45)), s * 0.22, col)
			_cap(Vector2(palm.position.x + s * 0.1, palm.position.y + s * 0.45), Vector2(palm.position.x - s * 0.4, palm.position.y + s * 0.05), s * 0.22, col)
		"kick":   # a boot swung up (drawn tilted around the centre)
			draw_set_transform(c, -0.45, Vector2.ONE)
			var boot := PackedVector2Array()
			for q: Vector2 in [Vector2(-0.6, -0.95), Vector2(-0.05, -0.95), Vector2(-0.05, 0.0), Vector2(0.55, 0.12),
					Vector2(0.78, 0.38), Vector2(0.7, 0.62), Vector2(-0.6, 0.62)]:
				boot.append(q * s * 0.9)
			draw_colored_polygon(boot, col)
			_cap(Vector2(-0.6, 0.78) * s * 0.9, Vector2(0.62, 0.78) * s * 0.9, w * 0.5, col)   # sole
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"recover":   # a spring under an up chevron (boing)
			_cap(c + Vector2(-s * 0.6, -s * 0.25), c + Vector2(0, -s * 0.85), w, col)
			_cap(c + Vector2(0, -s * 0.85), c + Vector2(s * 0.6, -s * 0.25), w, col)
			var zz := PackedVector2Array()
			for k in 5:
				zz.append(c + Vector2((-0.45 if k % 2 == 0 else 0.45) * s, (0.0 + k * 0.22) * s))
			draw_polyline(zz, col, w * 0.7, true)
			_cap(c + Vector2(-s * 0.6, s * 0.98), c + Vector2(s * 0.6, s * 0.98), w * 0.7, col)
		"dash":   # speed lines + chevron
			_cap(c + Vector2(-s * 0.95, -s * 0.4), c + Vector2(-s * 0.35, -s * 0.4), w * 0.6, col)
			_cap(c + Vector2(-s * 1.05, 0), c + Vector2(-s * 0.2, 0), w * 0.6, col)
			_cap(c + Vector2(-s * 0.95, s * 0.4), c + Vector2(-s * 0.35, s * 0.4), w * 0.6, col)
			_cap(c + Vector2(s * 0.1, -s * 0.65), c + Vector2(s * 0.75, 0), w, col)
			_cap(c + Vector2(s * 0.75, 0), c + Vector2(s * 0.1, s * 0.65), w, col)
		"pause":
			_cap(c + Vector2(-s * 0.4, -s * 0.6), c + Vector2(-s * 0.4, s * 0.6), s * 0.42, col)
			_cap(c + Vector2(s * 0.4, -s * 0.6), c + Vector2(s * 0.4, s * 0.6), s * 0.42, col)
