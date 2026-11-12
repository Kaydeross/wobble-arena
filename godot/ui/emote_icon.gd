class_name EmoteIcon
extends Control
## A vector icon per emote (no image files, no emoji font): a rarity-coloured disc with a white glyph drawn from
## lines, arcs and polygons. Used by the Locker / Shop emote cards and the in-match emote wheel (EmoteIcon.paint).
## Unknown ids get a generic star, so a new emote never shows a blank card.

var id := ""
var rarity_col := Color.WHITE

func _init(p_id: String = "", min_size: float = 64.0) -> void:
	id = p_id
	rarity_col = LockerData.rarity_color(LockerData.emote_rarity(p_id))
	custom_minimum_size = Vector2(min_size, min_size)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var r := minf(size.x, size.y) * 0.5 - 2.0
	if r <= 4.0: return
	var c := size / 2.0
	draw_circle(c, r, Color(rarity_col, 0.95))
	draw_circle(c, r * 0.86, Color(rarity_col.darkened(0.55), 1.0))
	paint(self, id, c, r * 0.62, Color.WHITE)

## Draws emote `eid`'s glyph on `ci`, centred on `c`, about `r` in radius.
static func paint(ci: CanvasItem, eid: String, c: Vector2, r: float, col: Color) -> void:
	var w := maxf(2.0, r * 0.16)                          # stroke width
	var P := func(x: float, y: float) -> Vector2: return c + Vector2(x, y) * r
	match eid:
		"wobble":                                         # a wobbly wave
			var pts := PackedVector2Array()
			for i in 17:
				var t := i / 16.0
				pts.append(P.call(-0.9 + 1.8 * t, sin(t * TAU * 1.5) * 0.35))
			ci.draw_polyline(pts, col, w, true)
		"hip":                                            # left-right arrows
			ci.draw_line(P.call(-0.85, 0), P.call(0.85, 0), col, w, true)
			for sx: float in [-1.0, 1.0]:
				ci.draw_colored_polygon(PackedVector2Array([P.call(sx * 0.95, 0), P.call(sx * 0.55, -0.32), P.call(sx * 0.55, 0.32)]), col)
			ci.draw_circle(P.call(0, -0.55), r * 0.18, col)
		"clap":                                           # two palms and spark lines
			for sx: float in [-1.0, 1.0]:
				ci.draw_set_transform(P.call(sx * 0.2, 0.15), sx * 0.35, Vector2(1, 1))
				ci.draw_rect(Rect2(Vector2(-r * 0.17, -r * 0.45), Vector2(r * 0.34, r * 0.9)), col)
				ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			for a: float in [-0.5, 0.0, 0.5]:
				var d := Vector2.UP.rotated(a)
				ci.draw_line(c + d * r * 0.62, c + d * r * 0.95, col, w * 0.8, true)
		"disco":                                          # pointing arrow and a star
			ci.draw_line(P.call(-0.7, 0.7), P.call(0.45, -0.45), col, w * 1.2, true)
			ci.draw_colored_polygon(PackedVector2Array([P.call(0.75, -0.75), P.call(0.2, -0.55), P.call(0.55, -0.2)]), col)
			_star(ci, P.call(-0.45, -0.45), r * 0.28, col)
		"sit":                                            # sunglasses
			for sx: float in [-1.0, 1.0]:
				ci.draw_rect(Rect2(P.call(sx * 0.48 - 0.36, -0.25), Vector2(r * 0.72, r * 0.5)), col)
			ci.draw_line(P.call(-0.15, -0.15), P.call(0.15, -0.15), col, w, true)
			ci.draw_arc(P.call(0, 0.25), r * 0.4, 0.4, PI - 0.4, 10, col, w, true)
		"robot":                                          # a robot head
			ci.draw_rect(Rect2(P.call(-0.6, -0.45), Vector2(r * 1.2, r * 1.05)), col, false, w)
			ci.draw_line(P.call(0, -0.45), P.call(0, -0.8), col, w, true)
			ci.draw_circle(P.call(0, -0.85), r * 0.12, col)
			for sx: float in [-1.0, 1.0]: ci.draw_rect(Rect2(P.call(sx * 0.27 - 0.1, -0.15), Vector2(r * 0.2, r * 0.2)), col)
			ci.draw_line(P.call(-0.3, 0.32), P.call(0.3, 0.32), col, w, true)
		"spin", "devspin", "sprinkler":                   # a circular arrow (+ code brackets / water drops)
			ci.draw_arc(c, r * 0.7, -PI * 0.3, PI * 1.35, 20, col, w, true)
			var tip := c + Vector2.from_angle(-PI * 0.3) * r * 0.7
			ci.draw_colored_polygon(PackedVector2Array([tip + Vector2(0, -r * 0.3), tip + Vector2(r * 0.3, r * 0.1), tip + Vector2(-r * 0.25, r * 0.15)]), col)
			if eid == "devspin":
				ci.draw_polyline(PackedVector2Array([P.call(-0.12, -0.25), P.call(-0.32, 0), P.call(-0.12, 0.25)]), col, w * 0.8, true)
				ci.draw_polyline(PackedVector2Array([P.call(0.12, -0.25), P.call(0.32, 0), P.call(0.12, 0.25)]), col, w * 0.8, true)
			elif eid == "sprinkler":
				for k in 3: ci.draw_circle(P.call(-0.25 + k * 0.25, 0.05 - absf(k - 1) * 0.12), r * 0.1, col)
		"flip", "cartwheel":                              # a loop arrow / a wheel with spokes
			if eid == "cartwheel":
				ci.draw_arc(c, r * 0.8, 0.0, TAU, 24, col, w, true)
				for k in 4: ci.draw_line(c, c + Vector2.from_angle(k * PI / 4.0 + 0.2) * r * 0.8, col, w * 0.7, true)
				for k in 4: ci.draw_line(c, c - Vector2.from_angle(k * PI / 4.0 + 0.2) * r * 0.8, col, w * 0.7, true)
			else:
				ci.draw_arc(P.call(0, -0.1), r * 0.55, PI * 0.15, PI * 1.85, 18, col, w, true)
				ci.draw_line(P.call(0, 0.45), P.call(0, 0.95), col, w, true)
				ci.draw_colored_polygon(PackedVector2Array([P.call(0.55, 0.05), P.call(0.2, -0.05), P.call(0.6, -0.35)]), col)
		"griddy", "floss", "jig":                         # zigzag steps / crossed arms / a music note
			if eid == "griddy":
				ci.draw_polyline(PackedVector2Array([P.call(-0.8, 0.5), P.call(-0.4, -0.3), P.call(0, 0.5), P.call(0.4, -0.3), P.call(0.8, 0.5)]), col, w, true)
			elif eid == "floss":
				ci.draw_line(P.call(-0.7, -0.7), P.call(0.7, 0.7), col, w * 1.2, true)
				ci.draw_line(P.call(-0.7, 0.7), P.call(0.7, -0.7), col, w * 1.2, true)
			else:
				ci.draw_circle(P.call(-0.25, 0.5), r * 0.25, col)
				ci.draw_line(P.call(-0.02, 0.5), P.call(-0.02, -0.7), col, w, true)
				ci.draw_colored_polygon(PackedVector2Array([P.call(-0.02, -0.75), P.call(0.55, -0.45), P.call(0.55, -0.2), P.call(-0.02, -0.45)]), col)
		"dab":                                            # head down, arm up
			ci.draw_circle(P.call(0.15, 0.1), r * 0.25, col)
			ci.draw_line(P.call(-0.1, 0.0), P.call(-0.75, -0.65), col, w * 1.3, true)
			ci.draw_line(P.call(0.35, -0.05), P.call(0.8, 0.45), col, w * 1.3, true)
		"pump", "flex":                                   # a fist with an up arrow / a dumbbell
			if eid == "pump":
				ci.draw_rect(Rect2(P.call(-0.35, 0.0), Vector2(r * 0.7, r * 0.6)), col)
				ci.draw_line(P.call(0, -0.1), P.call(0, -0.7), col, w, true)
				ci.draw_colored_polygon(PackedVector2Array([P.call(0, -0.95), P.call(-0.3, -0.55), P.call(0.3, -0.55)]), col)
			else:
				ci.draw_line(P.call(-0.55, 0), P.call(0.55, 0), col, w, true)
				for sx: float in [-1.0, 1.0]:
					ci.draw_rect(Rect2(P.call(sx * 0.6 - 0.12, -0.45), Vector2(r * 0.24, r * 0.9)), col)
					ci.draw_rect(Rect2(P.call(sx * 0.85 - 0.08, -0.28), Vector2(r * 0.16, r * 0.56)), col)
		"shimmy":                                         # shake lines either side of a body
			ci.draw_circle(P.call(0, -0.45), r * 0.22, col)
			ci.draw_rect(Rect2(P.call(-0.25, -0.18), Vector2(r * 0.5, r * 0.75)), col)
			for sx: float in [-1.0, 1.0]:
				for k in 2:
					var x := sx * (0.48 + k * 0.22)
					ci.draw_polyline(PackedVector2Array([P.call(x, -0.4), P.call(x + sx * 0.08, -0.15), P.call(x, 0.1), P.call(x + sx * 0.08, 0.35)]), col, w * 0.6, true)
		"betahop":                                        # a bug
			ci.draw_circle(P.call(0, 0.12), r * 0.42, col)
			ci.draw_circle(P.call(0, -0.42), r * 0.2, col)
			for sx: float in [-1.0, 1.0]:
				for k in 3: ci.draw_line(P.call(sx * 0.3, -0.12 + k * 0.25), P.call(sx * 0.75, -0.3 + k * 0.32), col, w * 0.6, true)
		"crane":                                          # a high kick: leg and foot
			ci.draw_line(P.call(-0.5, 0.8), P.call(-0.2, 0.0), col, w * 1.3, true)
			ci.draw_line(P.call(-0.2, 0.0), P.call(0.7, -0.55), col, w * 1.3, true)
			ci.draw_colored_polygon(PackedVector2Array([P.call(0.6, -0.75), P.call(0.95, -0.55), P.call(0.75, -0.35)]), col)
			ci.draw_circle(P.call(-0.3, -0.45), r * 0.2, col)
		"land":                                           # a down arrow hitting the ground
			ci.draw_line(P.call(0, -0.85), P.call(0, 0.15), col, w * 1.2, true)
			ci.draw_colored_polygon(PackedVector2Array([P.call(0, 0.45), P.call(-0.35, 0.05), P.call(0.35, 0.05)]), col)
			ci.draw_line(P.call(-0.85, 0.65), P.call(0.85, 0.65), col, w, true)
			for sx: float in [-1.0, 1.0]: ci.draw_line(P.call(sx * 0.45, 0.45), P.call(sx * 0.75, 0.2), col, w * 0.6, true)
		"guitar":                                         # a guitar
			ci.draw_circle(P.call(-0.25, 0.3), r * 0.38, col)
			ci.draw_circle(P.call(0.02, 0.0), r * 0.27, col)
			ci.draw_line(P.call(0.05, -0.05), P.call(0.75, -0.75), col, w * 1.1, true)
			ci.draw_circle(P.call(-0.2, 0.25), r * 0.11, Color(0, 0, 0, 0.6))
		"galaxy", "nova":                                 # a star in a ring / a burst
			if eid == "galaxy":
				_star(ci, c, r * 0.55, col)
				ci.draw_arc(c, r * 0.85, -0.6, PI - 0.9, 14, col, w * 0.7, true)
			else:
				for k in 8:
					var d := Vector2.from_angle(k * TAU / 8.0)
					ci.draw_line(c + d * r * 0.45, c + d * r * 0.95, col, w * 0.8, true)
				ci.draw_circle(c, r * 0.35, col)
		"wheelie":                                        # a bike on its back wheel
			ci.draw_arc(P.call(-0.5, 0.4), r * 0.35, 0.0, TAU, 14, col, w * 0.8, true)
			ci.draw_arc(P.call(0.45, -0.25), r * 0.35, 0.0, TAU, 14, col, w * 0.8, true)
			ci.draw_line(P.call(-0.5, 0.4), P.call(0.45, -0.25), col, w, true)
			ci.draw_line(P.call(0.0, 0.1), P.call(-0.1, -0.35), col, w, true)
		"salute":                                         # a flag
			ci.draw_line(P.call(-0.5, 0.85), P.call(-0.5, -0.8), col, w, true)
			ci.draw_colored_polygon(PackedVector2Array([P.call(-0.5, -0.8), P.call(0.7, -0.5), P.call(-0.5, -0.15)]), col)
		"bow":                                            # a bow tie
			for sx: float in [-1.0, 1.0]:
				ci.draw_colored_polygon(PackedVector2Array([c, P.call(sx * 0.85, -0.45), P.call(sx * 0.85, 0.45)]), col)
			ci.draw_circle(c, r * 0.18, col)
		"zombie":                                         # a face with X eyes
			ci.draw_arc(c, r * 0.8, 0.0, TAU, 24, col, w, true)
			for sx: float in [-1.0, 1.0]:
				var e: Vector2 = P.call(sx * 0.32, -0.2)
				var k := r * 0.14
				ci.draw_line(e + Vector2(-k, -k), e + Vector2(k, k), col, w * 0.7, true)
				ci.draw_line(e + Vector2(-k, k), e + Vector2(k, -k), col, w * 0.7, true)
			ci.draw_polyline(PackedVector2Array([P.call(-0.35, 0.35), P.call(-0.12, 0.25), P.call(0.12, 0.38), P.call(0.35, 0.28)]), col, w * 0.7, true)
		"storm":                                          # a lightning bolt
			ci.draw_colored_polygon(PackedVector2Array([P.call(0.15, -0.95), P.call(-0.5, 0.1), P.call(-0.05, 0.1), P.call(-0.2, 0.95), P.call(0.5, -0.2), P.call(0.05, -0.2), P.call(0.3, -0.95)]), col)
		"pirouette":                                      # a flower of petals
			for k in 5:
				ci.draw_circle(c + Vector2.from_angle(k * TAU / 5.0 - PI / 2.0) * r * 0.45, r * 0.3, col)
			ci.draw_circle(c, r * 0.22, Color("#ffd24a"))
		_:
			_star(ci, c, r * 0.8, col)

static func _star(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for k in 10:
		pts.append(c + Vector2.from_angle(-PI / 2.0 + k * PI / 5.0) * (r if k % 2 == 0 else r * 0.45))
	ci.draw_colored_polygon(pts, col)

## Every emote id that has its own glyph (the rest draw the generic star).
const GLYPHS := ["wobble", "hip", "clap", "disco", "sit", "robot", "spin", "devspin", "sprinkler", "flip", "cartwheel",
	"griddy", "floss", "jig", "dab", "pump", "flex", "shimmy", "betahop", "crane", "land", "guitar", "galaxy", "nova",
	"wheelie", "salute", "bow", "zombie", "storm", "pirouette"]
