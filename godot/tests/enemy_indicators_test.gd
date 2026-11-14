extends SceneTree
## Off-screen enemy indicator test (headless): the HUD's small arrows for living hostile fighters that are outside the
## camera view (ui/enemy_indicators.gd, Settings > Gameplay > Enemy arrows). Checks that a fighter behind the camera gets
## a marker on its side of the screen, an in-view fighter gets none, dead / left / eliminated fighters get none, team
## mates and Arcade co-op seats get none, ghosts count as enemies, the cap of 6 holds with a fixed pool (no node leaks
## after hide / show), close enemies are spread and faded, the markers stay inside the safe area and clear of the HUD
## panels and the touch buttons at 667x375, 812x375, 1024x768 and 1366x1024, and the setting and the pause / results
## state hide the whole layer.
##   godot --headless --path godot --script res://tests/enemy_indicators_test.gd -- --no-save   (npm run test:godot-ui)

const FRAME := 1.0 / 60.0
## window size in points, safe-area insets in points (left, top, right, bottom): the sizes the owner asked for
const SIZES := [
	[Vector2(667, 375), [0.0, 0.0, 0.0, 0.0]],       # iPhone SE / 8
	[Vector2(812, 375), [44.0, 0.0, 44.0, 21.0]],    # iPhone X / 13 mini
	[Vector2(1024, 768), [0.0, 20.0, 0.0, 0.0]],     # iPad landscape
	[Vector2(1366, 1024), [0.0, 24.0, 0.0, 20.0]],   # iPad Pro 12.9
]

var fails := 0
var world: Node
var hud: Control
var ind: Node              # untyped: the script's members are read dynamically (MAX_MARKERS, markers, shown)
var st: Node

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL ", what)

func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _run() -> void:
	st = root.get_node("Settings")
	SafeArea.override = []
	st.set_value("touch_mode", "off")        # desktop HUD for the arrow maths; the touch blockers are checked below
	st.set_value("enemy_arrows", true)
	world = load("res://world/world.tscn").instantiate()
	world.auto_run = false
	world.bot_count = 7                      # 8 fighters: more than the marker cap
	world.rng_seed = 77
	root.add_child(world)
	await process_frame
	await process_frame
	hud = world.hud
	ind = hud.get_node_or_null("EnemyIndicators")
	check(ind != null, "the HUD builds the EnemyIndicators layer")
	if ind == null:
		print("UI enemy indicators FAILED (no layer)")
		quit(1)
		return
	check(ind.get_child_count() == ind.MAX_MARKERS and ind.markers.size() == ind.MAX_MARKERS,
		"six marker nodes are pooled up front (%d children, %d markers)" % [ind.get_child_count(), ind.markers.size()])
	check(ind.get_index() < hud.get_node("Score").get_index() and ind.get_index() < hud.get_node("Radar").get_index()
		and ind.get_index() < hud.get_node("Health").get_index() and ind.get_index() < hud.get_node("Hotbar").get_index(),
		"the arrows are drawn under the HUD panels")
	_settle()
	_hide_all()
	_settle()
	check(_visible().size() == 0, "no enemies, no arrows")
	# --- an enemy in view gets no arrow
	_hide_all()
	var e: FighterState = world.sim.fighters[1]
	_show(e)
	_place_rel(e, 0.0, 9.0)                  # 9 m in front of the camera, on the ground: on screen
	_settle()
	check(_visible().size() == 0, "an enemy in front / in view gets no arrow")
	# --- behind the camera, right and left: a marker, on the matching side, inside the safe area
	_place_rel(e, 10.0, -3.0)                # behind the camera and to its right
	_settle()
	var vis := _visible()
	check(vis.size() == 1, "an enemy behind the camera gets one arrow (%d)" % vis.size())
	if vis.size() == 1:
		var safe := SafeArea.rect(hud.get_viewport())
		var r: Rect2 = _rect(vis[0])
		check(safe.grow(0.5).encloses(r), "the behind arrow %s is inside the safe area %s" % [r, safe])
		check(r.get_center().x > safe.get_center().x, "an enemy behind-right gets an arrow on the right half")
		check(_near_edge(r, safe), "the behind arrow sits at the screen edge")
	_place_rel(e, -10.0, -3.0)               # behind and to the left
	_settle()
	vis = _visible()
	check(vis.size() == 1, "a behind-left enemy gets one arrow")
	if vis.size() == 1:
		var safe2 := SafeArea.rect(hud.get_viewport())
		check(_rect(vis[0]).get_center().x < safe2.get_center().x, "an enemy behind-left gets an arrow on the left half")
	# --- above the view (in front, off the top of the frustum) points up
	_place_rel(e, 0.0, 6.0, 40.0)
	_settle()
	vis = _visible()
	check(vis.size() == 1, "an enemy above the view gets an arrow")
	if vis.size() == 1:
		var safe3 := SafeArea.rect(hud.get_viewport())
		check(_rect(vis[0]).get_center().y < safe3.get_center().y, "the above arrow points up")
	# --- dead / left / eliminated enemies get none
	for state: String in ["dead", "left", "elim"]:
		_hide_all()
		_show(e)
		_place_rel(e, 10.0, -3.0)
		match state:
			"dead": e.dead = true
			"left": e.left = true
			"elim": e.elim = true
		_settle()
		check(_visible().size() == 0, "a %s enemy gets no arrow" % state)
		_show(e)
	# --- a ghost fighter is an enemy too (online matches)
	_hide_all()
	_show(e)
	e.is_ghost = true
	_place_rel(e, 10.0, -3.0)
	_settle()
	check(_visible().size() == 1, "a ghost fighter behind the camera gets an arrow")
	e.is_ghost = false
	# --- team mates and Arcade co-op seats get none
	_hide_all()
	_show(e)
	_place_rel(e, 10.0, -3.0)
	world.sim.combat.teams = 2
	e.team = world.sim.player.team
	_settle()
	check(_visible().size() == 0, "a team mate gets no arrow")
	e.team = (world.sim.player.team + 1) % 2
	_settle()
	check(_visible().size() == 1, "the other team gets an arrow")
	world.sim.combat.teams = 0
	e.team = -1
	world.sim.combat.pve_seats = [e]
	_settle()
	check(_visible().size() == 0, "an Arcade co-op seat gets no arrow")
	world.sim.combat.pve_seats = []
	# --- clustering: two enemies aimed the same way keep apart and the slid one fades
	_hide_all()
	var a: FighterState = world.sim.fighters[1]
	var b: FighterState = world.sim.fighters[2]
	_show(a); _show(b)
	_place_rel(a, 6.0, -8.0)                 # nearer
	_place_rel(b, 6.2, -8.0)                 # almost the same direction: same rim spot
	_settle()
	vis = _visible()
	check(vis.size() == 2, "two close enemies both keep an arrow (%d)" % vis.size())
	if vis.size() == 2:
		var r0 := _rect(vis[0])
		var r1 := _rect(vis[1])
		var gap := r0.get_center().distance_to(r1.get_center())
		check(gap >= ind.MIN_SEP - 0.5, "clustered arrows spread along the rim (%.1f px)" % gap)
		check(not r0.grow(-0.5).intersects(r1), "clustered arrows do not overlap")
		var alphas: Array = [float(vis[0].modulate.a), float(vis[1].modulate.a)]
		check(alphas[1] < alphas[0], "the slid arrow fades (%s)" % [alphas])
	# --- cap + fixed pool: 7 off-screen enemies show exactly 6, the node count never changes
	_hide_all()
	for i in 7:
		var f: FighterState = world.sim.fighters[i + 1]
		_show(f)
		_place_rel(f, -12.0 + float(i) * 4.0, -8.0 - float(i % 2))   # a fan behind the camera
	_settle()
	var kids := ind.get_child_count()
	var hud_kids := hud.get_child_count()
	check(ind.shown == ind.MAX_MARKERS, "the cap shows %d of 7 off-screen enemies (%d)" % [ind.MAX_MARKERS, ind.shown])
	check(_visible().size() == ind.MAX_MARKERS, "exactly %d marker nodes are visible" % ind.MAX_MARKERS)
	check(kids == ind.MAX_MARKERS, "no marker node is added past the pool (%d)" % kids)
	check(_clear_of_ui(), "the arrows keep clear of the HUD and the touch buttons")
	for i in 30:
		world._update_hud(FRAME)
	check(ind.get_child_count() == kids and hud.get_child_count() == hud_kids, "repeated frames allocate no nodes")
	# --- hide / show cycles leak nothing
	for i in 5:
		st.set_value("enemy_arrows", false)
		_settle()
		st.set_value("enemy_arrows", true)
		_settle()
	check(ind.get_child_count() == kids and hud.get_child_count() == hud_kids, "hide / show leaks no nodes")
	check(ind.markers.size() == ind.MAX_MARKERS and not (ind.markers[0] as Node).is_queued_for_deletion(),
		"the pool is intact after hide / show")
	# --- Settings > Gameplay > Enemy arrows off hides them, on brings them back
	_hide_all()
	_show(world.sim.fighters[1])
	_place_rel(world.sim.fighters[1], 10.0, -3.0)
	st.set_value("enemy_arrows", false)
	_settle()
	check(_visible().size() == 0, "Settings enemy_arrows off hides the arrows")
	st.set_value("enemy_arrows", true)
	_settle()
	check(_visible().size() == 1, "Settings enemy_arrows on shows them again")
	# --- paused / results: no arrows behind the menu
	world.paused = true
	_settle()
	check(_visible().size() == 0, "paused hides the arrows")
	world.paused = false
	_settle()
	check(_visible().size() == 1, "unpausing brings them back")
	# --- safe areas at the owner's sizes, with and without phone insets
	var tier: Node = root.get_node("Tier")
	var size0 := root.size
	var ins0: Array = SafeArea.override
	tier.force_ui_scale = true
	for c: Array in SIZES:
		var win: Vector2 = c[0]
		root.size = Vector2i(win)
		tier.apply_ui_scale()
		await process_frame
		var vs := root.get_visible_rect().size
		var k := vs.x / win.x
		SafeArea.override = (c[1] as Array).map(func(v: float) -> float: return v * k)
		world.touch._update_insets()
		hud._update_insets()
		_hide_all()
		for i in 4:
			var f: FighterState = world.sim.fighters[i + 1]
			_show(f)
			_place_rel(f, -10.0 + float(i) * 6.0, -6.0 - float(i))    # around the back, all off screen
		_settle()
		var n := 0
		for m in ind.markers:
			var mc: Control = m
			if not mc.visible: continue
			n += 1
			var safe := SafeArea.rect(hud.get_viewport())
			check(safe.grow(0.5).encloses(_rect(mc)), "%s: arrow %s inside the safe area %s" % [win, _rect(mc), safe])
		check(n >= 2, "%s: enemy arrows are shown (%d)" % [win, n])
		check(_clear_of_ui(), "%s: arrows stay clear of the HUD panels" % win)
		print("UI enemy arrows %dx%d canvas %dx%d checked (%d shown)" % [win.x, win.y, vs.x, vs.y, n])
	root.size = size0
	tier.force_ui_scale = false
	root.content_scale_factor = 1.0
	SafeArea.override = ins0
	await process_frame
	world.touch._update_insets()
	hud._update_insets()
	_settle()
	# --- with the touch layer on the arrows stay clear of the touch buttons, pause and emote buttons
	st.set_value("touch_mode", "on")
	world.touch.visible = true                     # the touch layer follows touch_mode on a real device; a test sets it
	await process_frame
	await process_frame
	world.touch._update_insets()
	hud._update_insets()
	_hide_all()
	for i in 4:
		var f: FighterState = world.sim.fighters[i + 1]
		_show(f)
		_place_rel(f, -12.0 + float(i) * 8.0, -8.0)         # a fan behind: markers land on the bottom / side edges
	_settle()
	check(world.touch.visible, "touch layer on")
	check(_visible().size() >= 1, "arrows still show with the touch layer on (%d)" % _visible().size())
	check(_clear_of_ui(), "with the touch layer on the arrows stay clear of the buttons")
	var n_touch := _visible().size()
	print("UI enemy arrows with the touch layer checked (%d shown)" % n_touch)
	world.touch.visible = false
	st.set_value("touch_mode", "off")
	# --- done
	world.free()
	await process_frame
	SafeArea.override = []
	print("UI ok (enemy indicators)")
	quit(0 if fails == 0 else 1)

# ---------------- helpers ----------------

## Put a fighter `x` metres along the camera's right and `z` metres along its forward (negative = behind) from the
## camera, with its feet on the player's ground (`dy` lifts it off the ground).
func _place_rel(f: FighterState, x: float, z: float, dy := 0.0) -> void:
	var cam: Camera3D = world.cam
	var b := cam.global_transform.basis
	var ground: float = world.sim.player.phys.py
	var p: Vector3 = cam.global_position + b.x * x - b.z * z
	f.phys.place(p.x, ground + dy, p.z)

## Camera + HUD for the frame, without stepping the sim (a test places the fighters itself).
func _settle() -> void:
	world.cam.follow(FRAME, world.cam_target(), false, world.solids)
	world._update_hud(0.0)

func _hide_all() -> void:
	for f: FighterState in world.sim.fighters:
		if f != world.sim.player: f.dead = true

func _show(f: FighterState) -> void:
	f.dead = false; f.left = false; f.elim = false

func _visible() -> Array:
	var out: Array = []
	for m in ind.markers:
		var mc: Control = m
		if mc.visible: out.append(mc)
	return out

func _rect(m: Control) -> Rect2:
	return m.get_global_rect()

func _near_edge(r: Rect2, safe: Rect2) -> bool:
	return absf(r.get_center().x - safe.end.x) <= 34.0 or absf(r.get_center().x - safe.position.x) <= 34.0 \
		or absf(r.get_center().y - safe.end.y) <= 34.0 or absf(r.get_center().y - safe.position.y) <= 34.0

## No visible arrow covers a HUD panel, the pause / emote button or a touch button (the layer's own contract).
func _clear_of_ui() -> bool:
	var ok := true
	var vis := _visible()
	var blocked := [world.touch.pause_rect()]
	if world.emote_wheel != null and world.emote_wheel.shown(): blocked.append(world.emote_wheel.button_rect())
	if world.touch.visible:
		for b: Array in world.touch.BUTTONS:
			var br: Array = world.touch.button_rect(b)
			blocked.append(Rect2(br[0] - Vector2(br[1], br[1]), Vector2(br[1], br[1]) * 2.0))
	for n: String in ["Score", "Radar", "Health", "Hotbar"]:
		var c: Control = hud.get_node(n)
		if c.visible and c.size.x > 1.0: blocked.append(Rect2(c.position, c.size * c.scale))
	var fd: Control = hud.get_node("Feed")
	if fd.get_child_count() > 0: blocked.append(Rect2(fd.position, fd.size))
	for m: Control in vis:
		for r: Rect2 in blocked:
			if _rect(m).grow(-0.5).intersects(r):
				ok = false
	return ok
