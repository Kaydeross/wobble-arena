class_name WobblerLooks
extends RefCounted
## Look data for the wobbler: class proportions/accessories (classes.json + Fighter.classLook), hats (makeHat),
## outfits (cosmetics.json skins + buildSkinParts). Ported from public/index.html (CODEMAP section 8).
##
## A part is [parent, geo, color, pos, rot, scale] (rot is a three.js XYZ Euler; scale/rot optional):
##   parent: "neck" | "body" | "leg0" | "leg1" | "armL" | "arm" | "hat" | "spin"
##   geo:    a LowPoly.from_spec array, e.g. ["box", w, h, d]
##   color:  int (fixed) | [mul, mix] (tinted from the outfit's top colour, hexMix) | "tone" | "toneD"
## Hats and outfits are tables keyed by id: adding one is adding an entry (or one builder for outfits).

const ACCENT := 0xffe0b3          # the wobbler's default skin/hands colour (player accent in the web game)
const DEFAULT_COLOR := 0x39b5a8
const EYE := 0x14222b
const BELT := 0x2a2f38
const BUCKLE := 0xf2c14e

static var _json: Dictionary = {}


## shared/<name>.json. Prefers the synced copy in res://data/ (foundation track, tools/sync-shared.js), else reads the
## repo's shared/ directly (editor and tests). TODO: switch to the Content autoload once it lands.
static func data(name: String) -> Dictionary:
	if _json.has(name):
		return _json[name]
	var path := "res://data/%s.json" % name
	if not FileAccess.file_exists(path):
		path = ProjectSettings.globalize_path("res://").path_join("../shared/%s.json" % name)
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(d) != TYPE_DICTIONARY:
		push_error("WobblerLooks: cannot read %s" % path)
		d = {}
	if name == "classes": ExtraClasses.merge(d)          # + the Godot-only classes (res://data/extra/classes.json)
	_json[name] = d
	return d


static func class_def(id: String) -> Dictionary:
	var c := data("classes")
	return c[id] if c.has(id) else c.get("wobbler", {"size": 1, "head": 1, "wide": 1, "wob": 1})


static func skin_def(key: String) -> Dictionary:
	return data("cosmetics").get("skins", {}).get(key, {})


## web hexMix: scale a colour, then mix it towards white
static func hex_mix(h: int, mul: float, mix: float) -> int:
	var out := 0
	for sh in [16, 8, 0]:
		var v: float = float((h >> sh) & 255) * mul
		v += (255.0 - v) * mix
		out |= clampi(roundi(v), 0, 255) << sh
	return out


# ---------------------------------------------------------------- hats (makeHat, ~3860). Group sits at neck y 0.62
const HAT_SPIN_Y := {"prop": 0.25}
const HATS := {
	"none": [],
	"party": [
		["hat", ["cone", 0.2, 0.55, 6], 0xe86fa5, [0, 0.25, 0], [0, 0, 0.1]],
		["hat", ["ico", 0.07, 0], 0xffd24a, [0.03, 0.55, 0]]],
	"top": [
		["hat", ["cyl", 0.4, 0.4, 0.05, 8], 0x23262d, [0, 0, 0]],
		["hat", ["cyl", 0.24, 0.26, 0.45, 8], 0x23262d, [0, 0.24, 0]],
		["hat", ["cyl", 0.265, 0.265, 0.1, 8], 0xe3566b, [0, 0.1, 0]]],
	"crown": [
		["hat", ["cyl", 0.27, 0.25, 0.2, 6], 0xffcf3a, [0, 0.08, 0]],
		["hat", ["cone", 0.06, 0.18, 4], 0xffcf3a, [0.22, 0.28, 0]],
		["hat", ["cone", 0.06, 0.18, 4], 0xffcf3a, [0.0679837, 0.28, 0.2092324]],
		["hat", ["cone", 0.06, 0.18, 4], 0xffcf3a, [-0.1779837, 0.28, 0.1293128]],
		["hat", ["cone", 0.06, 0.18, 4], 0xffcf3a, [-0.1779837, 0.28, -0.1293128]],
		["hat", ["cone", 0.06, 0.18, 4], 0xffcf3a, [0.0679837, 0.28, -0.2092324]]],
	"prop": [
		["hat", ["cyl", 0.26, 0.28, 0.14, 8], 0x4a90d9, [0, 0.04, 0]],
		["hat", ["cyl", 0.03, 0.03, 0.14, 4], 0xcfd8de, [0, 0.17, 0]],
		["spin", ["box", 0.7, 0.03, 0.12], 0xe3566b, [0, 0, 0]],
		["spin", ["box", 0.12, 0.03, 0.7], 0xffd24a, [0, 0, 0]]],
	"wizard": [
		["hat", ["cyl", 0.42, 0.42, 0.04, 8], 0x5a3fa0, [0, 0, 0]],
		["hat", ["cone", 0.27, 0.95, 7], 0x6a4cc0, [0, 0.48, 0], [0, 0, -0.12]],
		["hat", ["ico", 0.05, 0], 0xffd24a, [0.05, 0.4, 0.26]]],
	"bunny": [
		["hat", ["box", 0.1, 0.5, 0.06], 0xf4f0f0, [-0.14, 0.3, 0]],
		["hat", ["box", 0.05, 0.38, 0.04], 0xf2a6b8, [-0.14, 0.3, 0.02]],
		["hat", ["box", 0.1, 0.5, 0.06], 0xf4f0f0, [0.14, 0.3, 0]],
		["hat", ["box", 0.05, 0.38, 0.04], 0xf2a6b8, [0.14, 0.3, 0.02]]],
	"cone": [
		["hat", ["cone", 0.26, 0.6, 8], 0xff7a2e, [0, 0.27, 0]],
		["hat", ["cyl", 0.17, 0.2, 0.1, 8], 0xffffff, [0, 0.22, 0]]],
	"pirate": [
		["hat", ["cyl", 0.3, 0.42, 0.22, 6], 0x1c1c22, [0, 0.1, 0]],
		["hat", ["box", 0.86, 0.05, 0.3], 0x1c1c22, [0, 0, 0]],
		["hat", ["box", 0.62, 0.04, 0.05], 0xe0b43a, [0, 0.19, 0.4]],
		["hat", ["box", 0.13, 0.11, 0.03], 0xf4f1e8, [0, 0.12, 0.42]],
		["hat", ["box", 0.03, 0.03, 0.035], 0x1c1c22, [-0.03, 0.13, 0.44]],
		["hat", ["box", 0.03, 0.03, 0.035], 0x1c1c22, [0.03, 0.13, 0.44]]],
	"chef": [
		["hat", ["cyl", 0.27, 0.26, 0.16, 8], 0xffffff, [0, 0.06, 0]],
		["hat", ["ico", 0.34, 0], 0xfafafa, [0, 0.36, 0]],
		["hat", ["box", 0.56, 0.035, 0.56], 0xe8e8e8, [0, 0.14, 0], [0, PI / 4, 0]]],
	"cowboy": [
		["hat", ["cyl", 0.5, 0.5, 0.04, 9], 0x9a6a3a, [0, 0, 0]],
		["hat", ["cyl", 0.25, 0.31, 0.3, 8], 0xa87646, [0, 0.17, 0]],
		["hat", ["cyl", 0.32, 0.32, 0.07, 8], 0x3b2615, [0, 0.07, 0]],
		["hat", ["box", 0.1, 0.05, 0.5], 0x9a6a3a, [-0.5, 0.06, 0], [0, 0, 0.5]],
		["hat", ["box", 0.1, 0.05, 0.5], 0x9a6a3a, [0.5, 0.06, 0], [0, 0, -0.5]]],
	"halo": [
		["hat", ["tor", 0.27, 0.035, 6, 16], 0xffe066, [0, 0.5, 0], [PI / 2, 0, 0], [1, 1, 1], {"glow": 0xffc400, "glow_k": 0.6}]],
	"viking": [
		["hat", ["sph", 0.36, 8, 5, 0, TAU, 0, PI / 2], 0x9aa3ad, [0, -0.05, 0]],
		["hat", ["cyl", 0.37, 0.37, 0.06, 8], 0x6e5a3c, [0, -0.03, 0]],
		["hat", ["cone", 0.075, 0.42, 6], 0xf0e6cf, [-0.4, 0.2, 0], [0, 0, 0.7]],
		["hat", ["cone", 0.075, 0.42, 6], 0xf0e6cf, [0.4, 0.2, 0], [0, 0, -0.7]]],
	"phones": [
		["hat", ["tor", 0.4, 0.035, 6, 14, PI], 0x23262d, [0, -0.28, 0]],
		["hat", ["cyl", 0.14, 0.14, 0.1, 10], 0xe3566b, [-0.4, -0.28, 0], [0, 0, PI / 2]],
		["hat", ["cyl", 0.1, 0.1, 0.04, 10], 0x23262d, [-0.46, -0.28, 0], [0, 0, PI / 2]],
		["hat", ["cyl", 0.14, 0.14, 0.1, 10], 0xe3566b, [0.4, -0.28, 0], [0, 0, PI / 2]],
		["hat", ["cyl", 0.1, 0.1, 0.04, 10], 0x23262d, [0.46, -0.28, 0], [0, 0, PI / 2]]],
	"beanie": [
		["hat", ["sph", 0.37, 8, 5, 0, TAU, 0, PI / 2], 0xe05a47, [0, -0.02, 0]],
		["hat", ["cyl", 0.385, 0.385, 0.11, 8], 0x2b2f3a, [0, 0, 0]],
		["hat", ["ico", 0.09, 0], 0xffffff, [0, 0.38, 0]]],
	"santa": [
		["hat", ["cone", 0.31, 0.62, 8], 0xd32f2f, [-0.04, 0.3, 0], [0, 0, 0.25]],
		["hat", ["cyl", 0.34, 0.34, 0.12, 8], 0xffffff, [0, 0.02, 0]],
		["hat", ["ico", 0.09, 0], 0xffffff, [0.13, 0.55, 0]]],
}


static func hat_parts(name: String) -> Array:
	return HATS.get(name, [])


# ---------------------------------------------------------------- class accessories (Fighter.classLook, ~5285)
## Returns parts for the class; `arm` = shoulder x (0.52 * wide), `deep` = torso depth scale.
static func class_parts(id: String, arm: float, deep: float) -> Array:
	match id:
		"bruiser":   # shoulder pads + headband
			return [
				["body", ["ico", 0.2, 0], 0x3a3f4a, [-(arm + 0.04), 0.84, 0]],
				["body", ["ico", 0.2, 0], 0x3a3f4a, [arm + 0.04, 0.84, 0]],
				["neck", ["tor", 0.36, 0.04, 4, 8], 0xe3403b, [0, 0.5, 0], [PI / 2, 0, 0]]]
		"kid":       # backpack + hair tuft
			return [
				["body", ["box", 0.46, 0.5, 0.22], 0xe3566b, [0, 0.45, -0.38 * deep]],
				["neck", ["cone", 0.07, 0.24, 4], 0x6b4423, [0.06, 0.74, 0.02], [0, 0, -0.35]]]
		"elder":     # side hair, bun, moustache, glasses, cane
			return [
				["neck", ["ico", 0.13, 0], 0xf4f4f4, [-0.34, 0.26, -0.04]],
				["neck", ["ico", 0.13, 0], 0xf4f4f4, [0.34, 0.26, -0.04]],
				["neck", ["ico", 0.16, 0], 0xf4f4f4, [0, 0.28, -0.3]],
				["neck", ["box", 0.3, 0.07, 0.09], 0xf4f4f4, [0, 0.2, 0.34]],
				["neck", ["tor", 0.095, 0.02, 4, 8], 0x2a2a2a, [-0.13, 0.36, 0.345], [0, 0, 0], [1, 1.1, 1]],
				["neck", ["tor", 0.095, 0.02, 4, 8], 0x2a2a2a, [0.13, 0.36, 0.345], [0, 0, 0], [1, 1.1, 1]],
				["neck", ["box", 0.1, 0.02, 0.02], 0x2a2a2a, [0, 0.38, 0.345]],
				["armL", ["cyl", 0.03, 0.03, 0.95, 5], 0x7a4f2a, [0, -0.95, 0.12]],
				["armL", ["tor", 0.09, 0.03, 4, 6, PI], 0x7a4f2a, [0.09, -0.47, 0.12]]]
		"alien":     # antennae (the big eyes and green skin are handled by the wobbler)
			return [
				["neck", ["cyl", 0.018, 0.018, 0.34, 4], 0x5fb760, [-0.14, 0.75, 0], [0, 0, 0.3]],
				["neck", ["ico", 0.075, 0], 0xffe14a, [-0.2, 0.93, 0]],
				["neck", ["cyl", 0.018, 0.018, 0.34, 4], 0x5fb760, [0.14, 0.75, 0], [0, 0, -0.3]],
				["neck", ["ico", 0.075, 0], 0xffe14a, [0.2, 0.93, 0]]]
		# ---- Godot-only classes (data/extra/classes.json)
		"tank":      # steel helmet with a brim, big square shoulder plates
			return [
				["neck", ["ico", 0.4, 1], 0x6b7a86, [0, 0.5, -0.04], [0, 0, 0], [1.04, 0.6, 1.06]],
				["neck", ["box", 0.56, 0.05, 0.2], 0x56626e, [0, 0.52, 0.28]],
				["body", ["box", 0.34, 0.12, 0.38], 0x6b7a86, [-(arm + 0.02), 0.88, 0]],
				["body", ["box", 0.34, 0.12, 0.38], 0x6b7a86, [arm + 0.02, 0.88, 0]]]
		"dash":      # green sweatband with a flapping tail, wrist bands
			return [
				["neck", ["tor", 0.36, 0.04, 4, 8], 0x3fd070, [0, 0.5, 0], [PI / 2, 0, 0]],
				["neck", ["box", 0.08, 0.3, 0.03], 0x3fd070, [0.08, 0.4, -0.38], [0.5, 0, 0.35]],
				["neck", ["box", 0.08, 0.24, 0.03], 0x2fae5a, [-0.06, 0.42, -0.37], [0.6, 0, -0.25]],
				["armL", ["cyl", 0.11, 0.11, 0.1, 6], 0x3fd070, [0, -0.6, 0]]]
		"ace":       # aviator shades and a bandolier
			return [
				["neck", ["box", 0.15, 0.09, 0.04], 0x1d232b, [-0.13, 0.37, 0.345]],
				["neck", ["box", 0.15, 0.09, 0.04], 0x1d232b, [0.13, 0.37, 0.345]],
				["neck", ["box", 0.12, 0.025, 0.03], 0xd9c27a, [0, 0.4, 0.35]],
				["body", ["box", 0.09, 0.62, 0.04], 0x7a4f2a, [0, 0.5, 0.39], [0, 0, 0.6]],
				["body", ["box", 0.06, 0.09, 0.05], 0xd9a63a, [-0.08, 0.56, 0.41], [0, 0, 0.6]],
				["body", ["box", 0.06, 0.09, 0.05], 0xd9a63a, [0.08, 0.44, 0.41], [0, 0, 0.6]]]
		"ghost":     # a pale sheet hood with a little curl on top
			return [
				["neck", ["ico", 0.4, 1], 0xf4f7ff, [0, 0.5, -0.06], [0, 0, 0], [1.05, 0.62, 1.1]],
				["neck", ["cone", 0.08, 0.22, 5], 0xf4f7ff, [0.04, 0.78, -0.04], [0, 0, -0.5]]]
		"champ":     # a gold title belt and a red headband
			return [
				["body", ["cyl", 0.43, 0.41, 0.15, 8], 0xf2c230, [0, 0.17, 0]],
				["body", ["box", 0.26, 0.2, 0.05], 0xffe14a, [0, 0.17, 0.41]],
				["body", ["box", 0.12, 0.1, 0.05], 0xe3403b, [0, 0.17, 0.44]],
				["neck", ["tor", 0.36, 0.035, 4, 8], 0xe3403b, [0, 0.5, 0], [PI / 2, 0, 0]]]
		"rampage":   # horns, angry brows, spiky shoulders
			return [
				["neck", ["cone", 0.07, 0.26, 5], 0xe8e0d0, [-0.22, 0.62, 0], [0, 0, 0.5]],
				["neck", ["cone", 0.07, 0.26, 5], 0xe8e0d0, [0.22, 0.62, 0], [0, 0, -0.5]],
				["neck", ["box", 0.16, 0.04, 0.04], 0x2a1d14, [-0.13, 0.46, 0.33], [0, 0, -0.35]],
				["neck", ["box", 0.16, 0.04, 0.04], 0x2a1d14, [0.13, 0.46, 0.33], [0, 0, 0.35]],
				["body", ["cone", 0.08, 0.24, 5], 0x3a3f4a, [-(arm + 0.02), 0.98, 0]],
				["body", ["cone", 0.08, 0.24, 5], 0x3a3f4a, [arm + 0.02, 0.98, 0]]]
	return []


# ---------------------------------------------------------------- outfits (buildSkinParts, ~4022)
## Outfits with a part builder below. The rest of cosmetics.json skins fall back to colours only (top/tone/pants/shoes)
## until their builders are ported.
const SKIN_BUILDERS := ["hoodie", "skater", "chef", "suit", "sporty", "tripleT", "ballerina", "assassino", "thunder"]

const T := [1.0, 0.0]
const T8 := [0.85, 0.0]
const T6 := [0.65, 0.0]
const L5 := [1.0, 0.5]
const L75 := [1.0, 0.75]


static func _r_at(y: float) -> float:          # torso radius at a height (its front is a ridge)
	return 0.34 + 0.06 * (y / 0.85)


static func _faces(out: Array, y: float, w: float, h: float, d: float, spec: Variant, off: float = 0.03) -> void:
	var r := _r_at(y)
	for sg in [-1.0, 1.0]:
		out.append(["body", ["box", w, h, d], spec, [sg * 0.433 * r + sg * 0.5 * off, y, 0.75 * r + 0.866 * off], [0, sg * PI / 6, 0]])


static func _cap(out: Array, col: Variant, y: float = 0.5, z: float = -0.06, sy: float = 0.55) -> void:
	out.append(["neck", ["ico", 0.4, 1], col, [0, y, z], [0, 0, 0], [1, sy, 1.05]])


static func _brim(out: Array, col: Variant, z: float, w: float = 0.36) -> void:
	out.append(["neck", ["box", w, 0.035, 0.24], col, [0, 0.5, z]])


static func skin_parts(key: String) -> Array:
	match key:                                  # outfits that replace the head and / or the torso (noHead / noTorso)
		"tripleT": return _triple_t()
		"ballerina": return _ballerina()
		"assassino": return _assassino()
		"thunder": return _thunder()
	var p := []
	var mouth := 0.165
	match key:
		"hoodie":
			_cap(p, 0x4a3222)
			p.append(["neck", ["box", 0.3, 0.1, 0.06], 0x4a3222, [0.06, 0.62, 0.34], [0, 0, -0.15]])
			p.append(["body", ["ico", 0.22, 1], T8, [0, 0.88, -0.2], [0, 0, 0], [1.4, 0.8, 0.8]])
			_faces(p, 0.2, 0.2, 0.16, 0.05, T8)
			p.append(["body", ["box", 0.03, 0.2, 0.03], 0xf2f2f2, [-0.07, 0.72, _r_at(0.72) + 0.02]])
			p.append(["body", ["box", 0.03, 0.2, 0.03], 0xf2f2f2, [0.07, 0.72, _r_at(0.72) + 0.02]])
		"skater":
			p.append(["neck", ["ico", 0.3, 1], 0x2a1d14, [0, 0.34, -0.14], [0, 0, 0], [1.05, 0.85, 0.9]])
			_cap(p, T, 0.52, -0.02)
			_brim(p, T, -0.3, 0.3)
			for k in 2:
				p.append(["leg%d" % k, ["cyl", 0.18, 0.19, 0.36, 6], 0xc9b37e, [0, -0.2, 0]])
			p.append(["body", ["box", 0.2, 0.2, 0.03], L5, [0, 0.5, _r_at(0.5) + 0.02]])
		"chef":
			p.append(["neck", ["cyl", 0.27, 0.25, 0.28, 8], L75, [0, 0.7, 0]])
			p.append(["neck", ["ico", 0.28, 1], L75, [0, 0.9, 0], [0, 0, 0], [1, 0.8, 1]])
			p.append(["neck", ["ico", 0.3, 1], 0x3b2a1e, [0, 0.33, -0.1], [0, 0, 0], [1.0, 0.8, 0.9]])
			p.append(["body", ["ico", 0.15, 1], T8, [0, 0.87, 0.1], [0, 0, 0], [1.5, 0.45, 1.2]])
			for k in 3:
				p.append(["body", ["box", 0.05, 0.05, 0.03], 0xd8d8d0, [0, 0.7 - k * 0.17, _r_at(0.7 - k * 0.17) + 0.02]])
		"suit":
			_cap(p, 0x15151a, 0.5, -0.06)
			p.append(["neck", ["box", 0.3, 0.07, 0.14], 0x15151a, [-0.08, 0.6, 0.3], [0, 0, 0.15]])
			p.append(["body", ["box", 0.2, 0.06, 0.1], 0xf2f2f2, [0, 0.86, 0.32], [0.3, 0, 0]])
			p.append(["body", ["box", 0.075, 0.5, 0.03], T6, [0, 0.55, _r_at(0.55) + 0.03]])
			p.append(["body", ["box", 0.1, 0.1, 0.04], T6, [0, 0.8, _r_at(0.8) + 0.03]])
			_faces(p, 0.66, 0.08, 0.34, 0.04, [1.0, 0.2], 0.035)
			p.append(["body", ["box", 0.05, 0.05, 0.03], 0xd9c27a, [-0.12, 0.3, _r_at(0.3)]])
		"sporty":
			_cap(p, 0xe8c872, 0.5, -0.06)
			p.append(["neck", ["cyl", 0.375, 0.375, 0.07, 10], T, [0, 0.47, 0]])
			_faces(p, 0.5, 0.3, 0.1, 0.035, 0xffffff, 0.03)
			for k in 2:
				p.append(["leg%d" % k, ["cyl", 0.18, 0.19, 0.36, 6], 0xf5f5f5, [0, -0.2, 0]])
				p.append(["leg%d" % k, ["cyl", 0.135, 0.125, 0.2, 6], 0xf5f5f5, [0, -0.62, 0]])
		_:
			return []
	# the face every outfit adds (the eyes are the wobbler's own): ears, nose, mouth sitting ON the flat-faced head
	for sx in [-1.0, 1.0]:
		p.append(["neck", ["box", 0.07, 0.13, 0.1], "toneD", [sx * 0.355, 0.32, 0]])
	p.append(["neck", ["box", 0.065, 0.075, 0.09], "toneD", [0, 0.285, 0.375]])
	var mz := maxf(head_surf(-0.055, mouth), maxf(head_surf(0.0, mouth), head_surf(0.055, mouth)))
	p.append(["neck", ["box", 0.11, 0.024, 0.05], 0x7a2c2c, [0, mouth, mz + 0.002]])
	return p


# ---- the mythic / legendary outfits that replace the head and / or torso (web buildSkinParts ~4610..4760). Ported
# with the plain LowPoly shapes (no lathes, no reactive faces: the "normal" face only), so they render as a complete
# figure; before this they only hid the head / torso and showed floating limbs.

## z of a cylinder's front at (x, y): radius going linearly from rb at y0 to rt at y1 (cups, mugs, logs).
static func _cyl_z(x: float, y: float, rb: float, rt: float, y0: float, y1: float) -> float:
	var r := lerpf(rb, rt, clampf((y - y0) / (y1 - y0), 0.0, 1.0))
	return sqrt(maxf(0.0001, r * r - x * x))


static func _triple_t() -> Array:                # Tung Tung Tung Sahur: a living wooden log with a big face
	const WD := 0xb07a43
	const WL := 0xd9a566
	const WK := 0x5a3a1c
	var p := [
		["body", ["cyl", 0.4, 0.4, 0.565, 12], WD, [0, 1.2825, 0]],      # head part of the log
		["body", ["cyl", 0.4, 0.37, 0.45, 12], WD, [0, 0.775, 0]],       # then a gentle taper to the legs
		["body", ["cyl", 0.37, 0.29, 0.635, 12], WD, [0, 0.2325, 0]],
		["body", ["cyl", 0.37, 0.37, 0.05, 12], WL, [0, 1.58, 0]],       # cut top with tree rings
		["body", ["tor", 0.2, 0.012, 4, 14], WK, [0, 1.61, 0], [PI / 2, 0, 0]],
		["body", ["tor", 0.1, 0.012, 4, 12], WK, [0, 1.61, 0], [PI / 2, 0, 0]],
		["body", ["ico", 0.07, 1], 0x9a6634, [0, 1.08, 0.4], [0, 0, 0], [1, 1.2, 0.8]],        # wooden nose
		["body", ["box", 0.34, 0.09, 0.05], 0x2a1208, [0, 0.9, 0.39]],                         # wide mouth, teeth
		["body", ["box", 0.3, 0.045, 0.055], 0xffffff, [0, 0.918, 0.395]]]
	for a: float in [0.5, 1.6, 2.7, 3.9, 5.0]:                                                 # wood grain
		p.append(["body", ["box", 0.02, 0.42, 0.012], 0x94652f, [sin(a) * 0.4, 1.15, cos(a) * 0.4], [0, a, 0]])
	for sx: float in [-1.0, 1.0]:
		p.append(["body", ["ico", 0.13, 1], 0xffffff, [sx * 0.17, 1.2, 0.34], [0, 0, 0], [1, 1.05, 0.5]])
		p.append(["body", ["ico", 0.06, 1], 0x111114, [sx * 0.17, 1.2, 0.41], [0, 0, 0], [1, 1, 0.6]])
		p.append(["body", ["box", 0.2, 0.05, 0.04], WK, [sx * 0.17, 1.38, 0.37], [0, 0, sx * 0.1]])
		p.append(["body", ["box", 0.08, 0.05, 0.05], 0x2a1208, [sx * 0.19, 0.935, 0.39], [0, 0, -sx * 0.65]])
	return p


static func _ballerina() -> Array:               # Ballerina Cappuccina: a cappuccino cup head, a pink tutu
	const CUP := 0xfbf6ee
	const FOAM := 0xf2dcc0
	const PK := 0xff8fc0
	const DK := 0x2a1612
	var cz := func(x: float, y: float) -> float: return _cyl_z(x, y, 0.33, 0.47, -0.03, 0.63)
	var p := [
		["neck", ["cyl", 0.47, 0.33, 0.66, 16], CUP, [0, 0.3, 0]],                 # the cup and its foot
		["neck", ["cyl", 0.335, 0.31, 0.08, 16], 0xe9dfd0, [0, -0.04, 0]],
		["neck", ["cyl", 0.43, 0.43, 0.03, 16], 0x8a5532, [0, 0.625, 0]],         # coffee, rim, cream
		["neck", ["tor", 0.455, 0.028, 6, 24], CUP, [0, 0.625, 0], [PI / 2, 0, 0]],
		["neck", ["cyl", 0.27, 0.27, 0.012, 16], FOAM, [0, 0.645, 0]],
		["neck", ["tor", 0.15, 0.04, 6, 12, PI * 1.5], CUP, [0.5, 0.3, 0], [0, 0, -PI * 0.75]],   # the handle
		["neck", ["box", 0.1, 0.024, 0.02], DK, [0, 0.19, cz.call(0.0, 0.19) + 0.006]],   # a small smile
		["neck", ["ico", 0.09, 1], PK, [0, 0.68, -0.4], [0, 0, 0], [1, 1, 0.8]],     # a pink bow at the back
		["body", ["cyl", 0.3, 0.2, 0.66, 16], 0xffc2da, [0, 0.5, 0]],             # slim leotard bodice
		["body", ["cyl", 0.31, 0.3, 0.05, 16], 0xffffff, [0, 0.82, 0]],
		["body", ["cyl", 0.24, 0.22, 0.06, 16], 0xffe3a0, [0, 0.17, 0]],          # gold waistband
		["body", ["tor", 0.66, 0.04, 6, 24], 0xffd0e4, [0, 0.06, 0], [PI / 2, 0, 0]]]   # tutu ruffle
	for l: Array in [[0.66, 0.06, PK, 0.09], [0.58, 0.13, 0xffb6d6, 0.08], [0.47, 0.2, 0xfff0f6, 0.07]]:   # pancake tutu
		p.append(["body", ["cyl", l[0] * 0.96, l[0], l[3], 20], l[2], [0, l[1], 0]])
	for sx: float in [-1.0, 1.0]:
		var ex := sx * 0.15
		var ya := atan2(ex, cz.call(ex, 0.34))
		p.append(["neck", ["ico", 0.058, 1], DK, [ex, 0.34, cz.call(ex, 0.34) + 0.012], [0, ya, 0], [1, 1.35, 0.4]])   # big eyes
		p.append(["neck", ["ico", 0.016, 0], 0xffffff, [ex - sx * 0.01, 0.365, cz.call(ex, 0.365) + 0.034], [0, ya, 0]])
		p.append(["neck", ["box", 0.07, 0.018, 0.02], DK, [sx * 0.205, 0.395, cz.call(sx * 0.205, 0.395) + 0.006], [0, atan2(sx * 0.205, cz.call(sx * 0.205, 0.395)), sx * 0.55]])
		var bx := sx * 0.25
		p.append(["neck", ["ico", 0.06, 1], 0xff9db8, [bx, 0.21, cz.call(bx, 0.21)], [0, atan2(bx, cz.call(bx, 0.21)), 0], [1.3, 0.8, 0.3]])   # blush
		p.append(["neck", ["box", 0.04, 0.024, 0.02], DK, [sx * 0.065, 0.2, cz.call(sx * 0.065, 0.2) + 0.006], [0, 0, -sx * 0.6]])
		p.append(["neck", ["ico", 0.06, 1], PK, [sx * 0.08, 0.68, -0.4], [0, 0, 0], [1, 1, 0.8]])
		p.append(["body", ["box", 0.05, 0.3, 0.04], 0xffffff, [sx * 0.1, 0.72, 0.28], [0.2, 0, 0]])   # straps
	for k in 2:                                                              # pointe-shoe ribbons up the shin
		p.append(["leg%d" % k, ["cyl", 0.1, 0.1, 0.05, 10], 0xffc4dc, [0, -0.42, 0]])
		for rz: float in [0.25, -0.25]:
			p.append(["leg%d" % k, ["box", 0.04, 0.5, 0.03], 0xffc4dc, [0, -0.62, 0.11], [0.1, 0, rz]])
	return p


static func _assassino() -> Array:               # Cappuccino Assassino: a ninja with a coffee mug for a head
	const MUG := 0xfaf4ea
	const BK := 0x17171f
	const BK2 := 0x2a2a36
	const RED := 0xc4202c
	const RED2 := 0x8f1620
	const STEEL := 0xc9d2dc
	const DK := 0x22160f
	const CLOTH := 0xf0ece4
	var mz := func(x: float, y: float) -> float: return _cyl_z(x, y, 0.37, 0.43, -0.08, 0.68)
	var p := [
		["neck", ["cyl", 0.43, 0.37, 0.76, 16], MUG, [0, 0.3, 0]],
		["neck", ["cyl", 0.375, 0.35, 0.07, 16], 0xdcd0bf, [0, -0.1, 0]],
		["neck", ["tor", 0.435, 0.03, 6, 24], MUG, [0, 0.68, 0], [PI / 2, 0, 0]],
		["neck", ["cyl", 0.41, 0.41, 0.03, 16], 0x4a2a14, [0, 0.665, 0]],
		["neck", ["cyl", 0.3, 0.3, 0.012, 16], 0xf3dfc2, [0, 0.683, 0]],
		["neck", ["box", 0.38, 0.012, 0.07], DK, [0, 0.692, 0], [0, PI / 4, 0]],          # a ninja star in the foam
		["neck", ["box", 0.38, 0.012, 0.07], DK, [0, 0.692, 0], [0, -PI / 4, 0]],
		["neck", ["tor", 0.16, 0.045, 6, 12, PI * 1.5], MUG, [0.45, 0.3, 0], [0, 0, -PI * 0.75]],   # the handle
		["neck", ["cyl", 0.44, 0.434, 0.14, 16], RED, [0, 0.5, 0]],                        # red headband
		["neck", ["box", 0.15, 0.15, 0.04], STEEL, [0, 0.5, 0.44]],                        # forehead plate
		["neck", ["ico", 0.085, 1], RED, [0, 0.5, -0.45]],                                  # knot and its tails
		["neck", ["box", 0.095, 0.62, 0.025], RED, [0.07, 0.23, -0.5], [0.34, 0, 0.14]],
		["neck", ["box", 0.095, 0.5, 0.025], RED, [-0.07, 0.29, -0.5], [0.32, 0, -0.2]],
		["body", ["cyl", 0.41, 0.33, 0.44, 16], BK, [0, 0.19, 0]],                          # the black ninja suit
		["body", ["cyl", 0.43, 0.41, 0.28, 16], BK, [0, 0.55, 0]],
		["body", ["cyl", 0.3, 0.43, 0.2, 16], BK, [0, 0.79, 0]],
		["body", ["cyl", 0.12, 0.3, 0.06, 16], BK, [0, 0.92, 0]],
		["body", ["tor", 0.405, 0.06, 6, 24], RED, [0, 0.13, 0], [PI / 2, 0, 0]],           # red sash
		["body", ["box", 0.1, 0.55, 0.03], RED, [0.3, -0.145, 0.3], [0.1, 0, 0.12]],
		["body", ["tor", 0.29, 0.095, 6, 20], RED, [0, 0.92, 0], [PI / 2, 0, 0]],           # the scarf
		["body", ["box", 0.2, 0.78, 0.03], RED, [0.14, 0.49, -0.44], [0.2, 0, 0.06]],
		["body", ["box", 0.075, 1.0, 0.085], BK2, [0, 0.5, -0.46], [0, 0, 0.65]],           # sword across the back
		["body", ["box", 0.065, 0.3, 0.07], RED, [-0.388, 1.0, -0.46], [0, 0, 0.65]],
		["body", ["box", 0.17, 0.03, 0.06], 0xd9a63a, [-0.31, 0.89, -0.46], [0, 0, 0.65]]]
	var rad := func(y: float) -> float:                                                   # the suit's radius at y
		if y < 0.41: return lerpf(0.33, 0.41, (y + 0.03) / 0.44)
		if y < 0.69: return lerpf(0.41, 0.43, (y - 0.41) / 0.28)
		return lerpf(0.43, 0.3, (y - 0.69) / 0.2)
	for sg: float in [-1.0, 1.0]:                                                         # crossed chest straps
		for i in 9:
			var t := i / 8.0
			var x := sg * (-0.26 + 0.52 * t)
			var y := 0.82 - 0.62 * t
			var r: float = rad.call(y)
			var z := sqrt(maxf(0.0001, r * r - x * x))
			p.append(["body", ["box", 0.1, 0.17, 0.035], RED2, [x, y, z + 0.005], [0, atan2(x, z), sg * 0.7]])
	for sx: float in [-1.0, 1.0]:                                                         # a cute face
		var ex := sx * 0.15
		var ya := atan2(ex, mz.call(ex, 0.27))
		p.append(["neck", ["ico", 0.07, 1], DK, [ex, 0.27, mz.call(ex, 0.27) + 0.006], [0, ya, 0], [1, 1.3, 0.35]])
		p.append(["neck", ["ico", 0.02, 0], 0xffffff, [ex + sx * 0.012, 0.305, mz.call(ex, 0.305) + 0.03], [0, ya, 0]])
		var cx := sx * 0.26
		p.append(["neck", ["ico", 0.055, 1], 0xff9db8, [cx, 0.17, mz.call(cx, 0.17)], [0, atan2(cx, mz.call(cx, 0.17)), 0], [1.3, 0.8, 0.3]])
		p.append(["neck", ["box", 0.045, 0.02, 0.02], DK, [sx * 0.035, 0.146, mz.call(sx * 0.035, 0.15) + 0.006], [0, 0, -sx * 0.55]])
		p.append(["neck", ["box", 0.1, 0.15, 0.04], STEEL, [sx * 0.118, 0.5, mz.call(sx * 0.118, 0.5) + 0.02], [0, sx * 0.32, 0]])
	for a in ["armL", "arm"]:                                                              # bandaged forearms
		for y: float in [-0.48, -0.62]:
			p.append([a, ["cyl", 0.118, 0.108, 0.1, 10], CLOTH, [0, y, 0]])
	for k in 2:
		p.append(["leg%d" % k, ["cyl", 0.138, 0.126, 0.13, 10], CLOTH, [0, -0.6, 0]])
		p.append(["leg%d" % k, ["cyl", 0.135, 0.125, 0.1, 10], CLOTH, [0, -0.45, 0]])
	return p


static func _thunder() -> Array:                 # Thunder Titan: gold storm armour, a winged helm, a white beard
	const GOLD := 0xf2c230
	const GOLD2 := 0xc9971c
	const STORM := 0x2b49c4
	const STORM2 := 0x1a2f86
	const WHITE := 0xf4f7ff
	const BOLT := 0xfffbb0
	var p := [
		["body", ["cyl", 0.43, 0.33, 0.38, 12], STORM, [0, 0.16, 0]],                       # storm suit
		["body", ["cyl", 0.46, 0.43, 0.3, 12], STORM, [0, 0.5, 0]],
		["body", ["cyl", 0.3, 0.46, 0.29, 12], STORM, [0, 0.795, 0]],
		["body", ["ico", 0.42, 1], GOLD2, [0, 0.6, 0.1], [0, 0, 0], [0.98, 0.82, 0.98]],    # gold cuirass
		["body", ["box", 0.08, 0.3, 0.04], BOLT, [0.02, 0.62, 0.47], [0, 0, 0.35], {"glow": BOLT, "glow_k": 0.8}],   # glowing bolt
		["body", ["box", 0.08, 0.2, 0.04], BOLT, [-0.04, 0.48, 0.46], [0, 0, -0.5], {"glow": BOLT, "glow_k": 0.8}],
		["body", ["tor", 0.43, 0.055, 6, 24], GOLD, [0, 0.12, 0], [PI / 2, 0, 0]],          # belt
		["body", ["box", 0.88, 1.2, 0.05], STORM2, [0, 0.38, -0.5], [0.08, 0, 0]],          # cape and collar
		["body", ["box", 0.9, 0.08, 0.07], GOLD, [0, 0.98, -0.47], [0.08, 0, 0]]]
	_cap(p, GOLD, 0.5, -0.06, 0.6)                                                         # the winged helmet
	p.append(["neck", ["cyl", 0.39, 0.39, 0.04, 10], GOLD2, [0, 0.45, 0]])
	p.append(["neck", ["box", 0.06, 0.26, 0.04], BOLT, [0, 0.85, 0], [0, 0, 0.3], {"glow": BOLT, "glow_k": 0.8}])
	for sx: float in [-1.0, 1.0]:
		p.append(["body", ["ico", 0.23, 1], GOLD, [sx * 0.52, 0.86, 0], [0, 0, 0], [1.15, 0.72, 1.15]])   # pauldrons
		p.append(["body", ["cone", 0.05, 0.22, 5], GOLD, [sx * 0.62, 1.06, 0], [0, 0, -sx * 0.45]])
		p.append(["neck", ["box", 0.3, 0.2, 0.03], WHITE, [sx * 0.44, 0.62, -0.06], [0, sx * 0.35, -sx * 0.5]])   # wings
		p.append(["neck", ["box", 0.22, 0.14, 0.03], WHITE, [sx * 0.5, 0.74, -0.1], [0, sx * 0.35, -sx * 0.8]])
		p.append(["neck", ["box", 0.17, 0.06, 0.05], WHITE, [sx * 0.13, 0.47, head_surf(sx * 0.13, 0.47) + 0.012], [0, 0, sx * 0.3]])   # brows
		p.append(["neck", ["ico", 0.065, 1], WHITE, [sx * 0.07, 0.22, head_surf(sx * 0.07, 0.22) + 0.04], [0, 0, sx * 0.3], [1.5, 0.7, 0.9]])   # moustache
	for b: Array in [[0, 0.1, 0.13], [0.14, 0.14, 0.11], [-0.14, 0.14, 0.11], [0.24, 0.2, 0.09], [-0.24, 0.2, 0.09], [0.09, 0.0, 0.1], [-0.09, 0.0, 0.1], [0, -0.05, 0.1]]:
		p.append(["neck", ["ico", b[2], 1], WHITE, [b[0], b[1], head_surf(b[0], maxf(b[1], 0.05)) + 0.035 - (0.03 if absf(b[0]) > 0.2 else 0.0)], [0, 0, 0], [1.1, 1, 1]])   # cloud beard
	for k in 2:
		p.append(["leg%d" % k, ["cyl", 0.17, 0.145, 0.3, 10], GOLD, [0, -0.58, 0]])      # greaves, knee guards
		p.append(["leg%d" % k, ["ico", 0.11, 1], GOLD, [0, -0.38, 0.12]])
	for a in ["armL", "arm"]:
		p.append([a, ["cyl", 0.128, 0.118, 0.2, 10], GOLD, [0, -0.5, 0]])                 # gold bracers
	return p


static var _head_tris: PackedVector3Array = PackedVector3Array()


## z of the head's real (flat-faced icosahedron) front surface at (x, y) in neck space (web headSurf).
static func head_surf(x: float, y: float) -> float:
	if _head_tris.is_empty():
		_head_tris = LowPoly.ico(0.36, 0).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var yy := y - 0.32
	var best := -INF
	for i in range(0, _head_tris.size(), 3):
		var a := _head_tris[i]
		var b := _head_tris[i + 1]
		var c := _head_tris[i + 2]
		var d := (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)
		if absf(d) < 1e-9:
			continue
		var l1 := ((b.y - c.y) * (x - c.x) + (c.x - b.x) * (yy - c.y)) / d
		var l2 := ((c.y - a.y) * (x - c.x) + (a.x - c.x) * (yy - c.y)) / d
		var l3 := 1.0 - l1 - l2
		if l1 < -1e-6 or l2 < -1e-6 or l3 < -1e-6:
			continue
		best = maxf(best, l1 * a.z + l2 * b.z + l3 * c.z)
	return sqrt(maxf(0.0, 0.1296 - yy * yy - x * x)) - 0.03 if best == -INF else best


# ---------------------------------------------------------------- held weapons (makeWeaponMesh, ~3522). Barrel/blade along local -Y
const WEAPON_PARTS := {
	"spatula": [
		["w", ["cyl", 0.065, 0.065, 0.45, 6], 0xe3566b, [0, 0, 0]],           # rubber grip
		["w", ["cyl", 0.035, 0.04, 1.0, 6], 0xb8c2c9, [0, -0.65, 0]],         # metal shaft
		["w", ["box", 0.58, 0.78, 0.05], 0xcfd8de, [0, -1.5, 0]],             # flat head
		["w", ["box", 0.07, 0.38, 0.07], 0x6b7a86, [-0.17, -1.58, 0]],
		["w", ["box", 0.07, 0.38, 0.07], 0x6b7a86, [0, -1.58, 0]],
		["w", ["box", 0.07, 0.38, 0.07], 0x6b7a86, [0.17, -1.58, 0]]],
	# placeholder for weapons not ported yet (weapons track): a plain grey gun block along the aim line
	"_generic": [
		["w", ["box", 0.14, 0.7, 0.18], 0x5a6270, [0, -0.3, -0.05]],
		["w", ["box", 0.1, 0.12, 0.22], 0x3a3f4a, [0, -0.02, 0.12]]],
}
