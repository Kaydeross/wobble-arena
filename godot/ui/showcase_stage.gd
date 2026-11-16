class_name ShowcaseStage
extends CharacterStage
## The title screen's 3D stage (ui/title_showcase.gd drives it): CharacterStage's lights and the real Wobbler in the
## player's look, on a round concrete site pedestal, beside a miniature tower crane that holds a DLC pack's hazard
## container over the pedestal. The container can be lowered, its two doors swung open, and its racks (the pack's
## weapons from the game's own held-weapon meshes, plus an arena badge) picked with a ray.
## Everything is posed from five numbers (see apply_pose), so the showcase's state machine can stop, reverse or restart
## an animation at any moment without leaving a half-built scene:
##   lower  0 = the container hangs at the hover height, 1 = it stands on the pedestal
##   doors  0 = shut and latched, 1 = both doors wide open
##   cam    0 = the idle framing (pedestal + crane inside `idle_rect`), 1 = close on the open container (`open_rect`)
##   hoist  0 = in view, 1 = pulled up out of the top of the picture (SWAP PACK changes the pack up there)
##   pop    a short 0..1 pulse for the selected weapon
## Cheap on a phone: the crane, the container shell and each door are ONE merged vertex-colour mesh each, a weapon is
## the Wobbler's fused single-mesh model, one shadowed sun + one rim (CharacterStage) + one small unshadowed lamp
## inside the container, and the landing dust is eight pooled low-poly blobs (no particle system).
## Headless (tests) nothing renders; the nodes, the pose and the ray maths are all still there.

const PED_R := 4.05                     ## pedestal radius
const BOX := Vector3(4.0, 2.1, 1.5)     ## container: width, height, depth
const HEAD_H := 0.34                    ## the header beam over the doors (carries the pack name)
const SILL_H := 0.08
const WALL := 0.08
const DOOR_OPEN := deg_to_rad(112.0)
const DOOR_OPEN_COMPACT := deg_to_rad(92.0)   ## portrait: the doors point at the camera, the picture is narrow
const COLS := 5
const ROWS := 2
const LAND := Vector3(1.55, 0.0, -0.35) ## the container's spot on the pedestal (its bottom centre)
const HOVER_Y := 2.45                   ## its bottom while it hangs
const HOIST_Y := 9.0                    ## extra lift when hoisted out of view
const RIG_H := 0.85                     ## slings: container roof to the hook
const MAST := Vector3(3.3, 0.0, -1.8)  ## crane mast foot (on the pedestal, behind the container's right end)
const MAST_H := 5.6
const MAST_W := 0.74
const JIB_Y := 5.75                     ## underside of the jib
const WOB_POS := Vector3(-2.75, 0.0, 0.85)
const WOB_POS_COMPACT := Vector3(-1.6, 0.0, 1.15)
const WOB_YAW := 0.42
const WOB_IDLE_POS := Vector3(-2.1, 0.0, 0.9)   ## the title's hero shot: the wobbler stands forward and big (docs/TITLE.md)
const WOB_IDLE_SCALE := 1.7
const WOB_IDLE_YAW := 0.3
const ELEV := deg_to_rad(8.0)           ## the camera looks this much down
const FOV := 30.0
## What each framing must show: [focus point, width, height] in metres.
const IDLE_VIEW := [Vector3(-1.2, 2.3, 0.0), 12.6, 6.4]   ## the hero shot: container top right, the wobbler centre left
const OPEN_VIEW := [Vector3(0.35, 1.25, 0.0), 8.4, 3.6]
const OPEN_VIEW_COMPACT := [Vector3(0.72, 1.3, 0.0), 6.1, 4.0]

const C_CONCRETE := Color("#9aa0a6")
const C_CONCRETE_D := Color("#7d848b")
const C_STEEL := Color("#4a4f55")
const C_DARK := Color("#2a2f36")
const C_PANEL := Color("#4a5560")
const C_GLASS := Color("#5f93aa")
const C_CRANE := Color("#f2c230")       ## SiteProps.YELLOW: the same crane yellow as the Building Site
const C_CRANE_D := Color("#d9a21b")

var pack: DLCPackData
var lower := 0.0
var doors := 0.0
var cam_k := 0.0
var hoist := 0.0
var pop := 0.0
var selected := -1                      ## rack cell of the weapon in hand (-1 = none)
var idle_rect := Rect2(0.0, 0.0, 1.0, 1.0)    ## where the idle scene sits in the picture (0..1 of the viewport): the title's safe area
var open_rect := Rect2(0.04, 0.16, 0.92, 0.6) ## where the open container sits
var compact := false: set = set_compact  ## portrait: the wobbler stands closer and the open framing is tighter
var weapon_ids: Array[String] = []      ## the rack, cell by cell (cell COLS * ROWS - 1 is the arena badge)

var _cam: Camera3D
var _cam_basis: Basis
var _shake := 0.0
var _t := 0.0
var _crate: Node3D                      ## the container (origin: bottom centre)
var _shell: MeshInstance3D
var _door_l: Node3D
var _door_r: Node3D
var _latch: Node3D
var _lamp: OmniLight3D
var _name_l: Label3D
var _arena_l: Label3D
var _rack: Node3D                       ## weapons + badge (rebuilt per pack)
var _slots: Array[Node3D] = []
var _hl: MeshInstance3D                 ## highlight plate behind the selected cell
var _cable: MeshInstance3D
var _dust: Array[MeshInstance3D] = []
var _dust_t := -1.0
var _stripe_mat: StandardMaterial3D
var _vc_mat: StandardMaterial3D
var _worn := ""                         ## the weapon the wobbler holds now
var _look_sig := ""

func _init() -> void:
	super._init()
	name = "ShowcaseStage"
	size = Vector2i(852, 393)
	var loop := Engine.get_main_loop()
	var tier: Node = (loop as SceneTree).root.get_node_or_null("Tier") if loop is SceneTree else null
	if tier != null and tier.has_method("is_mobile"):
		msaa_3d = Viewport.MSAA_2X if tier.is_mobile() else (Viewport.MSAA_DISABLED if tier.is_web() else Viewport.MSAA_4X)

func _ready() -> void:
	super._ready()
	_cam = get_node("Cam") as Camera3D
	_cam.fov = FOV
	_cam_basis = Basis(Vector3.RIGHT, -ELEV)
	_cam.basis = _cam_basis
	var sun := get_node("Sun") as DirectionalLight3D
	sun.directional_shadow_max_distance = 60.0
	_vc_mat = StandardMaterial3D.new()
	_vc_mat.vertex_color_use_as_albedo = true
	_vc_mat.vertex_color_is_srgb = true
	_vc_mat.roughness = 1.0
	_build_pedestal()
	_build_crane()
	_build_container()
	_build_dust()
	_pivot.position = WOB_POS_COMPACT if compact else WOB_POS
	_pivot.rotation.y = WOB_YAW
	dress("")
	apply_pose()

# ---------------------------------------------------------------- building blocks

## One flat-shaded box into `st`: `size`, placed by `xf`, vertex colour `c`.
static func add_box(st: SurfaceTool, bsize: Vector3, xf: Transform3D, c: Color) -> void:
	var h := bsize * 0.5
	var faces := [
		[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)], [Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0)],
		[Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)], [Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)],
		[Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1)], [Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)]]
	for f: Array in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var o := n * h
		var p: Array = [o - u * h - v * h, o + u * h - v * h, o + u * h + v * h, o - u * h + v * h]
		var wn := (xf.basis * n).normalized()
		for i: int in [0, 2, 1, 0, 3, 2]:      # clockwise seen from outside (Godot's front face)
			st.set_normal(wn)
			st.set_color(c)
			st.add_vertex(xf * (p[i] as Vector3))

## A box between two points (a strut): `t` thick.
static func add_strut(st: SurfaceTool, a: Vector3, b: Vector3, t: float, c: Color) -> void:
	var d := b - a
	var l := d.length()
	if l < 0.001: return
	var y := d / l
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT).normalized()
	add_box(st, Vector3(t, l, t), Transform3D(Basis(x, y, x.cross(y)), (a + b) * 0.5), c)

func _commit(st: SurfaceTool, node_name: String, parent: Node) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = st.commit()
	mi.material_override = _vc_mat
	parent.add_child(mi)
	return mi

static func _begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st

## Diagonal warning stripes (accent / black), drawn once into a small texture; triplanar so any box wears them evenly.
static func stripe_material(accent: Color) -> StandardMaterial3D:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var dark := Color(ConstructionStyle.BLACK)
	for y in n:
		for x in n:
			img.set_pixel(x, y, accent if ((x + y) % n) < n / 2 else dark)
	img.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(1.6, 1.6, 1.6)
	m.roughness = 1.0
	return m

func _build_pedestal() -> void:
	var ped := get_node("Pedestal") as MeshInstance3D
	var cm := CylinderMesh.new()
	cm.top_radius = PED_R; cm.bottom_radius = PED_R + 0.08; cm.height = 0.34; cm.radial_segments = 28
	ped.mesh = cm
	var pm := StandardMaterial3D.new()
	pm.albedo_color = C_CONCRETE
	pm.roughness = 1.0
	ped.material_override = pm
	ped.position.y = -0.17
	var rim := MeshInstance3D.new()                       # hazard-striped kerb round the slab
	rim.name = "Kerb"
	var rc := CylinderMesh.new()
	rc.top_radius = PED_R + 0.1; rc.bottom_radius = PED_R + 0.1; rc.height = 0.16; rc.radial_segments = 28
	rim.mesh = rc
	_stripe_mat = stripe_material(ConstructionStyle.YELLOW)
	rim.material_override = _stripe_mat
	rim.position.y = -0.42
	add_child(rim)
	var base := MeshInstance3D.new()
	base.name = "Base"
	var bc := CylinderMesh.new()
	bc.top_radius = PED_R + 0.22; bc.bottom_radius = PED_R + 0.5; bc.height = 0.3; bc.radial_segments = 28
	base.mesh = bc
	var bm := StandardMaterial3D.new()
	bm.albedo_color = C_CONCRETE_D
	bm.roughness = 1.0
	base.material_override = bm
	base.position.y = -0.65
	add_child(base)

## The tower crane: a lattice mast on the pedestal, a slewing cab, a jib that reaches over the container and a
## counter-jib with its weights. One merged mesh; the trolley, hook and cable move with the container.
func _build_crane() -> void:
	var st := _begin()
	var hw := MAST_W * 0.5
	var m := MAST
	add_box(st, Vector3(1.3, 0.22, 1.3), Transform3D(Basis(), m + Vector3(0, 0.11, 0)), C_CONCRETE_D)   # foot
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			add_box(st, Vector3(0.09, MAST_H, 0.09), Transform3D(Basis(), m + Vector3(sx * hw, MAST_H * 0.5, sz * hw)), C_CRANE)
	var bays := 8
	var bh := MAST_H / bays
	for i in bays:
		var y0 := i * bh
		var y1 := y0 + bh
		var flip := 1.0 if i % 2 == 0 else -1.0
		for side in 4:
			var b := Basis(Vector3.UP, side * PI * 0.5)
			var p0 := m + b * Vector3(-hw * flip, y0, hw)
			var p1 := m + b * Vector3(hw * flip, y1, hw)
			add_strut(st, p0, p1, 0.05, C_CRANE_D)
			add_strut(st, m + b * Vector3(-hw, y1, hw), m + b * Vector3(hw, y1, hw), 0.05, C_CRANE)
	# the top turns to face the container: jib along `dir`
	var to := Vector3(LAND.x - m.x, 0.0, LAND.z - m.z)
	var dir := to.normalized()
	var side_v := Vector3.UP.cross(dir)
	var top := m + Vector3(0, MAST_H, 0)
	var bx := Basis(dir, Vector3.UP, dir.cross(Vector3.UP))
	add_box(st, Vector3(1.15, 0.26, 1.15), Transform3D(bx, top + Vector3(0, 0.13, 0)), C_DARK)                 # slewing ring
	add_box(st, Vector3(0.8, 0.75, 0.62), Transform3D(bx, top + Vector3(0, 0.62, 0) + side_v * 0.62), C_CRANE)  # cab
	add_box(st, Vector3(0.5, 0.36, 0.05), Transform3D(bx, top + Vector3(0, 0.7, 0) + side_v * 0.95 + dir * 0.1), C_GLASS)
	var jib_l := to.length() + 2.6
	var cj_l := 2.4
	var jy := JIB_Y - MAST_H                                  # jib underside above the mast top
	for s: float in [-1.0, 1.0]:                             # two bottom chords
		add_strut(st, top + Vector3(0, jy, 0) + side_v * s * 0.3 - dir * cj_l, top + Vector3(0, jy, 0) + side_v * s * 0.3 + dir * jib_l, 0.08, C_CRANE)
	var apex := top + Vector3(0, jy + 1.25, 0)
	add_strut(st, top + Vector3(0, 0.26, 0), apex, 0.12, C_CRANE)                                             # tower head
	var chord_end := top + Vector3(0, jy + 0.5, 0) + dir * jib_l
	add_strut(st, top + Vector3(0, jy + 0.5, 0) + dir * 0.2, chord_end, 0.07, C_CRANE)                        # top chord
	var n := 9
	for i in n:                                              # zigzag between the chords
		var a0 := float(i) / n * jib_l
		var a1 := float(i + 1) / n * jib_l
		for s: float in [-1.0, 1.0]:
			add_strut(st, top + Vector3(0, jy, 0) + side_v * s * 0.3 + dir * a0, top + Vector3(0, jy + 0.5, 0) + dir * ((a0 + a1) * 0.5), 0.04, C_CRANE_D)
			add_strut(st, top + Vector3(0, jy + 0.5, 0) + dir * ((a0 + a1) * 0.5), top + Vector3(0, jy, 0) + side_v * s * 0.3 + dir * a1, 0.04, C_CRANE_D)
	add_strut(st, apex, chord_end, 0.035, C_STEEL)                                                            # tie bars
	add_strut(st, apex, top + Vector3(0, jy + 0.1, 0) - dir * cj_l, 0.035, C_STEEL)
	add_box(st, Vector3(1.0, 0.7, 0.8), Transform3D(bx, top + Vector3(0, jy - 0.3, 0) - dir * (cj_l - 0.5)), C_CONCRETE_D)   # counterweights
	add_box(st, Vector3(0.5, 0.2, 0.74), Transform3D(bx, top + Vector3(0, jy - 0.1, 0) + dir * to.length()), C_DARK)        # trolley
	_commit(st, "Crane", self)
	_cable = MeshInstance3D.new()
	_cable.name = "Cable"
	var cb := BoxMesh.new()
	cb.size = Vector3(0.05, 1.0, 0.05)
	_cable.mesh = cb
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = C_DARK
	cmat.roughness = 1.0
	_cable.material_override = cmat
	add_child(_cable)

## The container: a shell (floor, back, ends, roof, header, sill, corner posts, the rack's back panel and shelf, the
## slings and the hook), two hinged doors, a lamp, the pack-name plate. Painted per pack by set_pack().
func _build_container() -> void:
	_crate = Node3D.new()
	_crate.name = "Container"
	add_child(_crate)
	_shell = MeshInstance3D.new()
	_shell.name = "Shell"
	_shell.material_override = _vc_mat
	_crate.add_child(_shell)
	_door_l = Node3D.new()
	_door_l.name = "DoorL"
	_door_l.position = Vector3(-BOX.x * 0.5, SILL_H, BOX.z * 0.5)
	_crate.add_child(_door_l)
	_door_r = Node3D.new()
	_door_r.name = "DoorR"
	_door_r.position = Vector3(BOX.x * 0.5, SILL_H, BOX.z * 0.5)
	_crate.add_child(_door_r)
	for d: Node3D in [_door_l, _door_r]:
		var mi := MeshInstance3D.new()
		mi.name = "Panel"
		mi.material_override = _vc_mat
		d.add_child(mi)
		var band := MeshInstance3D.new()                    # the warning stripes along the door's foot
		band.name = "Band"
		var bm := BoxMesh.new()
		bm.size = Vector3(BOX.x * 0.5 - 0.06, 0.34, 0.03)
		band.mesh = bm
		band.position = Vector3((BOX.x * 0.25) * (1.0 if d == _door_l else -1.0), 0.2, 0.05)
		d.add_child(band)
	_latch = Node3D.new()                                   # the bar across the seam: swings up before the doors move
	_latch.name = "Latch"
	_latch.position = Vector3(-0.32, 0.95, 0.075)
	_door_r.add_child(_latch)
	var lm := MeshInstance3D.new()
	var lb := BoxMesh.new()
	lb.size = Vector3(0.62, 0.09, 0.05)
	lm.mesh = lb
	lm.position = Vector3(-0.2, 0, 0)
	var lmat := StandardMaterial3D.new()
	lmat.albedo_color = C_DARK
	lmat.roughness = 1.0
	lm.material_override = lmat
	_latch.add_child(lm)
	_lamp = OmniLight3D.new()
	_lamp.name = "Lamp"
	_lamp.position = Vector3(0, BOX.y - HEAD_H - 0.25, BOX.z * 0.5 + 0.5)
	_lamp.omni_range = 4.2
	_lamp.light_color = Color(1.0, 0.93, 0.78)
	_lamp.light_energy = 0.0
	_lamp.shadow_enabled = false
	_crate.add_child(_lamp)
	_name_l = Label3D.new()
	_name_l.name = "Name"
	_name_l.font = UiTheme.font(700)
	_name_l.font_size = 96
	_name_l.pixel_size = 0.0024
	_name_l.outline_size = 0
	_name_l.shaded = false
	_name_l.double_sided = false
	_name_l.position = Vector3(0, BOX.y - HEAD_H * 0.5, BOX.z * 0.5 + 0.012)
	_crate.add_child(_name_l)
	_hl = MeshInstance3D.new()
	_hl.name = "Highlight"
	var hb := BoxMesh.new()
	hb.size = Vector3(cell_size().x - 0.08, cell_size().y - 0.1, 0.02)
	_hl.mesh = hb
	var hm := StandardMaterial3D.new()
	hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hm.albedo_color = ConstructionStyle.YELLOW
	_hl.material_override = hm
	_hl.visible = false
	_crate.add_child(_hl)
	_rack = Node3D.new()
	_rack.name = "Rack"
	_crate.add_child(_rack)

func _build_dust() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.86, 0.84, 0.78)
	mat.roughness = 1.0
	var mesh := LowPoly.ico(1.0, 0)
	for i in 8:
		var d := MeshInstance3D.new()
		d.name = "Dust%d" % i
		d.mesh = mesh
		d.material_override = mat
		d.visible = false
		d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(d)
		_dust.append(d)

# ---------------------------------------------------------------- the pack

static func cell_size() -> Vector2:
	return Vector2((BOX.x - 2.0 * WALL) / COLS, (BOX.y - HEAD_H - SILL_H) / ROWS)

## Centre of rack cell `i` in the container's space (row 0 is the top row).
static func cell_centre(i: int) -> Vector3:
	var cs := cell_size()
	var c := i % COLS
	var r := i / COLS
	return Vector3(-BOX.x * 0.5 + WALL + (c + 0.5) * cs.x, SILL_H + (ROWS - 1 - r + 0.5) * cs.y, 0.0)

## The cell's pick box in the container's space (the whole depth of the container, so a tap anywhere in the cell counts).
static func cell_aabb(i: int) -> AABB:
	var cs := cell_size()
	var c := cell_centre(i)
	return AABB(Vector3(c.x - cs.x * 0.5, c.y - cs.y * 0.5, -BOX.z * 0.5), Vector3(cs.x, cs.y, BOX.z))

static func box_aabb() -> AABB:
	return AABB(Vector3(-BOX.x * 0.5, 0.0, -BOX.z * 0.5), BOX)

func arena_cell() -> int:
	return COLS * ROWS - 1

## Paints the container for `p` and hangs its weapons on the rack (old rack nodes are freed).
func set_pack(p: DLCPackData) -> void:
	pack = p
	selected = -1
	_hl.visible = false
	var accent := p.accent_color if p != null else ConstructionStyle.YELLOW
	var body := accent
	var body_d := accent.darkened(0.2)
	_stripe_mat_for(accent)
	# shell
	var st := _begin()
	var w := BOX.x; var h := BOX.y; var d := BOX.z
	add_box(st, Vector3(w, WALL, d), Transform3D(Basis(), Vector3(0, WALL * 0.5, 0)), C_STEEL)                    # floor
	add_box(st, Vector3(w, WALL, d), Transform3D(Basis(), Vector3(0, h - WALL * 0.5, 0)), body_d)                 # roof
	add_box(st, Vector3(w, h, WALL), Transform3D(Basis(), Vector3(0, h * 0.5, -d * 0.5 + WALL * 0.5)), body)      # back
	for s: float in [-1.0, 1.0]:
		add_box(st, Vector3(WALL, h, d), Transform3D(Basis(), Vector3(s * (w - WALL) * 0.5, h * 0.5, 0)), body)   # ends
		add_box(st, Vector3(0.12, h + 0.04, 0.12), Transform3D(Basis(), Vector3(s * (w * 0.5 - 0.03), h * 0.5, d * 0.5 - 0.03)), C_DARK)   # front posts
		for k in 4:                                                                                                # corrugation on the ends
			add_box(st, Vector3(0.03, h - 0.3, 0.1), Transform3D(Basis(), Vector3(s * (w * 0.5 + 0.012), h * 0.5, -d * 0.5 + 0.3 + k * 0.3)), body_d)
	add_box(st, Vector3(w, HEAD_H, 0.1), Transform3D(Basis(), Vector3(0, h - HEAD_H * 0.5, d * 0.5 - 0.05)), Color(ConstructionStyle.BLACK))   # header (name plate)
	add_box(st, Vector3(w, SILL_H, 0.1), Transform3D(Basis(), Vector3(0, SILL_H * 0.5, d * 0.5 - 0.05)), C_DARK)   # sill
	var back_z := -d * 0.5 + WALL + 0.02
	add_box(st, Vector3(w - 2 * WALL, h - 2 * WALL, 0.04), Transform3D(Basis(), Vector3(0, h * 0.5, back_z)), C_PANEL)   # rack back panel
	var cs := cell_size()
	add_box(st, Vector3(w - 2 * WALL, 0.05, d * 0.55), Transform3D(Basis(), Vector3(0, SILL_H + cs.y, -d * 0.5 + WALL + d * 0.275)), C_STEEL)   # shelf
	for c in range(1, COLS):                                                                                       # dividers
		add_box(st, Vector3(0.03, h - HEAD_H - SILL_H, 0.3), Transform3D(Basis(), Vector3(-w * 0.5 + WALL + c * cs.x, SILL_H + (h - HEAD_H - SILL_H) * 0.5, -d * 0.5 + WALL + 0.15)), C_STEEL)
	var hook := Vector3(0, h + RIG_H, 0)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			add_strut(st, Vector3(sx * (w * 0.5 - 0.15), h, sz * (d * 0.5 - 0.12)), hook, 0.035, C_DARK)       # slings
	add_box(st, Vector3(0.26, 0.3, 0.2), Transform3D(Basis(), hook + Vector3(0, 0.12, 0)), C_CRANE)                # hook block
	_shell.mesh = st.commit()
	# doors
	for dn: Node3D in [_door_l, _door_r]:
		var dir := 1.0 if dn == _door_l else -1.0             # the panel reaches from its hinge toward the seam
		var dw := w * 0.5
		var dh := h - HEAD_H - SILL_H
		var ds := _begin()
		add_box(ds, Vector3(dw - 0.02, dh, 0.06), Transform3D(Basis(), Vector3(dir * dw * 0.5, dh * 0.5, 0)), body)
		for k in 5:
			add_box(ds, Vector3(0.07, dh - 0.5, 0.03), Transform3D(Basis(), Vector3(dir * (0.25 + k * 0.36), dh * 0.5 + 0.17, 0.04)), body_d)
		add_box(ds, Vector3(0.04, dh - 0.1, 0.04), Transform3D(Basis(), Vector3(dir * (dw - 0.22), dh * 0.5, 0.055)), C_DARK)   # locking bar
		(dn.get_node("Panel") as MeshInstance3D).mesh = ds.commit()
		(dn.get_node("Band") as MeshInstance3D).material_override = _stripe_mat
		(dn.get_node("Band") as MeshInstance3D).visible = p == null or p.container_style != "plain"
	_name_l.modulate = accent
	# rack
	for c in _rack.get_children(): c.free()
	_slots.clear()
	weapon_ids.clear()
	_arena_l = null
	if p == null:
		relabel()
		return
	var ids := p.real_weapons(Content.weapons)
	for i in mini(ids.size(), COLS * ROWS - 1):
		weapon_ids.append(ids[i])
		var slot := Node3D.new()
		slot.name = "Slot_" + ids[i]
		slot.position = cell_centre(i) + Vector3(0, 0, -BOX.z * 0.5 + 0.42)
		_rack.add_child(slot)
		slot.add_child(_weapon_model(ids[i], cs))
		_slots.append(slot)
	_build_badge(p, cs)
	relabel()
	apply_pose()

## The words painted on the container (the pack name, the arena's name) in the current language.
func relabel() -> void:
	if pack == null:
		_name_l.text = ""
		return
	_name_l.text = TranslationServer.translate(pack.display_name).to_upper()
	if _arena_l != null and is_instance_valid(_arena_l):
		_arena_l.text = TranslationServer.translate(str(Content.get_map(pack.arena_id).get("name", pack.arena_id))).to_upper()

func _stripe_mat_for(accent: Color) -> void:
	var fresh := stripe_material(accent)
	_stripe_mat.albedo_texture = fresh.albedo_texture     # the kerb shares it: one material, repainted

## A weapon for a rack cell: the same fused single mesh the Wobbler holds, turned side-on, tilted and scaled to the cell.
func _weapon_model(id: String, cs: Vector2) -> Node3D:
	var holder := Node3D.new()
	holder.name = "Model"
	var mesh: ArrayMesh = Wobbler._weapon_visual(id)
	var basis := Basis(Vector3.BACK, deg_to_rad(58.0)) * Basis(Vector3.UP, -PI * 0.5)   # barrel up-right, top side up
	if mesh == null or mesh.get_surface_count() == 0:
		var fb := WeaponModels.build(id)
		fb.basis = basis
		holder.add_child(fb)
		return holder
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = Wobbler._shared_material("w")
	var bb := mesh.get_aabb()
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for k in 8:
		var c := basis * bb.get_endpoint(k)
		lo = lo.min(c); hi = hi.max(c)
	var ext := hi - lo
	var s := minf((cs.x - 0.1) / maxf(ext.x, 0.01), (cs.y - 0.12) / maxf(ext.y, 0.01))
	mi.basis = basis.scaled(Vector3.ONE * s)
	mi.position = -(lo + hi) * 0.5 * s
	holder.add_child(mi)
	return holder

## The arena badge in the last cell: the arena's own thumbnail in a dark frame with its name under it.
func _build_badge(p: DLCPackData, cs: Vector2) -> void:
	var slot := Node3D.new()
	slot.name = "Arena"
	slot.position = cell_centre(arena_cell()) + Vector3(0, 0, -BOX.z * 0.5 + 0.3)
	_rack.add_child(slot)
	var frame := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(cs.x - 0.1, cs.y - 0.12, 0.05)
	frame.mesh = fm
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(ConstructionStyle.BLACK)
	fmat.roughness = 1.0
	frame.material_override = fmat
	slot.add_child(frame)
	var tp := "res://ui/map_thumbs/%s.jpg" % p.arena_id
	if ResourceLoader.exists(tp):
		var pic := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(cs.x - 0.18, (cs.x - 0.18) * 0.5)
		pic.mesh = qm
		var pmat := StandardMaterial3D.new()
		pmat.albedo_texture = load(tp)
		pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		pic.material_override = pmat
		pic.position = Vector3(0, 0.1, 0.03)
		slot.add_child(pic)
	var l := Label3D.new()
	l.font = UiTheme.font(700)
	l.font_size = 64
	l.pixel_size = 0.0016
	l.outline_size = 0
	l.shaded = false
	l.modulate = p.accent_color
	_arena_l = l
	l.position = Vector3(0, -cs.y * 0.5 + 0.17, 0.035)
	slot.add_child(l)
	_slots.append(slot)

# ---------------------------------------------------------------- the wobbler

## The player's own wobbler (class, outfit, hat, colour from Settings), holding `weapon` ("" = empty hands). While it
## holds a pack weapon it also wears the pack's hat (`badge_icon`), preview only: nothing is written to Settings.
func dress(weapon: String) -> void:
	var lk := look()
	var cid := str(Settings.get_value("class", "wobbler"))
	if not Content.classes.has(cid): cid = "wobbler"
	var hat := str(lk["hat"])
	if weapon != "" and pack != null and pack.badge_icon != "": hat = pack.badge_icon
	var sig := "%s|%s|%s|%d" % [cid, lk["skin"], hat, int(lk["color"])]
	if sig != _look_sig:
		_look_sig = sig
		_wob.setup(cid, lk["skin"], hat, lk["color"])
	if weapon != _worn or _wob.weapon != weapon:
		_worn = weapon
		_wob.set_weapon(weapon)
	var aim := Vector3(0.25, 0.12, 1.0) if weapon != "" else Vector3(0, -0.4, 1)
	_wob.apply_state({"pos": Vector3.ZERO, "vel": Vector3.ZERO, "yaw": 0.0, "grounded": true, "aim": aim})
	if renders():
		for i in 40: _wob.animate(1.0 / 60.0)
	current = cid

func held_weapon() -> String:
	return _worn

func wobbler() -> Wobbler:
	return _wob

## Puts rack cell `i`'s weapon in the wobbler's hand (-1 = nothing) and lights the cell.
func select(i: int) -> void:
	selected = i if i >= 0 and i < weapon_ids.size() else -1
	_hl.visible = selected >= 0
	if selected >= 0:
		_hl.position = cell_centre(selected) + Vector3(0, 0, -BOX.z * 0.5 + WALL + 0.06)
		pop = 1.0
	dress(weapon_ids[selected] if selected >= 0 else "")

## The look changed elsewhere (Walldrobe): dress again.
func refresh_look() -> void:
	_look_sig = ""
	dress(_worn)

# ---------------------------------------------------------------- the pose

func set_compact(v: bool) -> void:
	if v == compact: return
	compact = v
	if _pivot != null: apply_pose()

func fit_camera() -> void:
	pass                                   # (CharacterStage fits one wobbler; this stage frames itself in apply_pose)

## Camera position that puts `view` ([focus, width, height]) inside `rect` (0..1 of the picture).
func frame_pos(view: Array, rect: Rect2) -> Vector3:
	var tan_v := tan(deg_to_rad(FOV * 0.5))
	var aspect := float(size.x) / float(maxi(1, size.y))
	var rw := maxf(rect.size.x, 0.05)
	var rh := maxf(rect.size.y, 0.05)
	var d := maxf(float(view[2]) / (2.0 * tan_v * rh), float(view[1]) / (2.0 * tan_v * aspect * rw))
	var hh := d * tan_v
	var hw := hh * aspect
	var cx := (rect.position.x + rect.size.x * 0.5) * 2.0 - 1.0
	var cy := 1.0 - (rect.position.y + rect.size.y * 0.5) * 2.0
	return (view[0] as Vector3) + _cam_basis.z * d - _cam_basis.x * (cx * hw) - _cam_basis.y * (cy * hh)

## Where the container's bottom centre is for the current pose.
func crate_pos() -> Vector3:
	var k := lower * lower * (3.0 - 2.0 * lower)
	return Vector3(LAND.x, lerpf(HOVER_Y, 0.0, k) + hoist * hoist * HOIST_Y, LAND.z)

func apply_pose() -> void:
	if _crate == null: return
	var hang := (1.0 - lower) * (1.0 - hoist)
	_crate.position = crate_pos() + Vector3(0, sin(_t * 1.3) * 0.05 * hang, 0)
	_crate.rotation = Vector3(0, sin(_t * 0.6) * 0.035 * hang, sin(_t * 0.9) * 0.022 * hang)
	var dk := clampf((doors - 0.2) / 0.8, 0.0, 1.0)
	dk = dk * dk * (3.0 - 2.0 * dk)
	var da := DOOR_OPEN_COMPACT if compact else DOOR_OPEN
	_door_l.rotation.y = -dk * da
	_door_r.rotation.y = dk * da
	_latch.rotation.z = -clampf(doors / 0.2, 0.0, 1.0) * PI * 0.5
	_lamp.light_energy = dk * 2.4
	_lamp.visible = dk > 0.01
	_rack.visible = doors > 0.02 or lower > 0.98     # shut and in the air: nothing inside needs drawing
	var top := _crate.position.y + BOX.y + RIG_H + 0.27
	var len := maxf(0.05, JIB_Y - 0.2 - top)
	_cable.scale = Vector3(1, len, 1)
	_cable.position = Vector3(LAND.x, top + len * 0.5, LAND.z)
	_cable.visible = top < JIB_Y - 0.2
	if selected >= 0 and selected < _slots.size():
		for i in _slots.size():
			_slots[i].scale = Vector3.ONE * ((1.1 + 0.12 * pop) if i == selected else 1.0)
	else:
		for s: Node3D in _slots: s.scale = Vector3.ONE
	var a := frame_pos(IDLE_VIEW, idle_rect)
	var b := frame_pos(OPEN_VIEW_COMPACT if compact else OPEN_VIEW, open_rect)
	var ck := cam_k * cam_k * (3.0 - 2.0 * cam_k)
	if _pivot != null:                       # the hero stands forward and big on the title and steps back to its rack place
		_pivot.position = WOB_IDLE_POS.lerp(WOB_POS_COMPACT if compact else WOB_POS, ck)
		_pivot.scale = Vector3.ONE * lerpf(WOB_IDLE_SCALE, 1.0, ck)
		_pivot.rotation.y = lerpf(WOB_IDLE_YAW, WOB_YAW, ck)
	_cam.position = a.lerp(b, ck) + Vector3(0, sin(_t * 47.0) * _shake * 0.08, 0)

## The landing: a ring of dust blobs and a small camera shake (the showcase plays the thud sound).
func thud() -> void:
	_dust_t = 0.0
	_shake = 1.0

func _process(dt: float) -> void:
	_t += dt
	_shake = maxf(0.0, _shake - dt * 4.0)
	pop = maxf(0.0, pop - dt * 3.0)
	_wob.animate(dt)
	if _dust_t >= 0.0:
		_dust_t += dt
		var k := _dust_t / 0.6
		for i in _dust.size():
			var d := _dust[i]
			d.visible = k < 1.0
			if k >= 1.0: continue
			var ang := TAU * float(i) / _dust.size() + 0.4
			var r := 1.6 + 1.5 * (1.0 - (1.0 - k) * (1.0 - k))
			d.position = Vector3(LAND.x + cos(ang) * r * 1.25, 0.12 + k * 0.5, LAND.z + sin(ang) * r * 0.6)
			d.scale = Vector3.ONE * (0.34 * sin(minf(1.0, k) * PI) + 0.02)
		if k >= 1.0: _dust_t = -1.0
	apply_pose()

func set_active(on: bool) -> void:
	active = on
	render_target_update_mode = SubViewport.UPDATE_ALWAYS if on and renders() else SubViewport.UPDATE_DISABLED
	set_process(on)

# ---------------------------------------------------------------- rays and projection (0..1 of the picture)

## The view ray through picture point `uv`: [origin, direction].
func ray(uv: Vector2) -> Array:
	var tan_v := tan(deg_to_rad(FOV * 0.5))
	var aspect := float(size.x) / float(maxi(1, size.y))
	var nx := uv.x * 2.0 - 1.0
	var ny := 1.0 - uv.y * 2.0
	var dir := (-_cam_basis.z + _cam_basis.x * (nx * tan_v * aspect) + _cam_basis.y * (ny * tan_v)).normalized()
	return [_cam.position, dir]

## Picture point of world point `p` (may lie outside 0..1).
func project(p: Vector3) -> Vector2:
	var tan_v := tan(deg_to_rad(FOV * 0.5))
	var aspect := float(size.x) / float(maxi(1, size.y))
	var v := _cam_basis.inverse() * (p - _cam.position)
	var z := maxf(0.01, -v.z)
	return Vector2((v.x / (z * tan_v * aspect)) * 0.5 + 0.5, 0.5 - (v.y / (z * tan_v)) * 0.5)

static func _ray_box(o: Vector3, d: Vector3, bb: AABB) -> float:
	var t0 := 0.0
	var t1 := INF
	for ax in 3:
		if absf(d[ax]) < 1e-6:
			if o[ax] < bb.position[ax] or o[ax] > bb.end[ax]: return -1.0
			continue
		var a := (bb.position[ax] - o[ax]) / d[ax]
		var b := (bb.end[ax] - o[ax]) / d[ax]
		t0 = maxf(t0, minf(a, b))
		t1 = minf(t1, maxf(a, b))
	return t0 if t0 <= t1 else -1.0

## What is under picture point `uv`: {"kind": "weapon", "index": cell} / {"kind": "arena"} / {"kind": "container"} / {}.
## The rack only answers while the doors are open.
func pick(uv: Vector2) -> Dictionary:
	var r := ray(uv)
	var inv := _crate.global_transform.affine_inverse()
	var o: Vector3 = inv * (r[0] as Vector3)
	var d: Vector3 = (inv.basis * (r[1] as Vector3)).normalized()
	if doors > 0.9:
		var best := -1
		var best_t := INF
		for i in COLS * ROWS:
			var t := _ray_box(o, d, cell_aabb(i))
			if t >= 0.0 and t < best_t:
				best_t = t; best = i
		if best == arena_cell(): return {"kind": "arena"}
		if best >= 0 and best < weapon_ids.size(): return {"kind": "weapon", "index": best}
	if _ray_box(o, d, box_aabb()) >= 0.0: return {"kind": "container"}
	return {}

## The picture rectangle (0..1) round a box given in the container's space.
func screen_rect(bb: AABB) -> Rect2:
	var xf := _crate.global_transform
	var lo := Vector2(INF, INF)
	var hi := -lo
	for k in 8:
		var p := project(xf * bb.get_endpoint(k))
		lo = lo.min(p); hi = hi.max(p)
	return Rect2(lo, hi - lo)

## The front face of rack cell `i` in the picture (0..1): what a finger aims at.
func cell_rect(i: int) -> Rect2:
	var bb := cell_aabb(i)
	return screen_rect(AABB(Vector3(bb.position.x, bb.position.y, BOX.z * 0.5), Vector3(bb.size.x, bb.size.y, 0.0)))
