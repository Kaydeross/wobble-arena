class_name AustraliaLooks
extends RefCounted
## "Hey Mate" Australia pack cosmetics: the Cork Slouch Hat, the Singlet + Shorts + Thongs outfit and the two Arcade victory hats
## (Normal: gold-corked slouch hat; Nightmare: a charred one with ember corks). Looks follow docs/img/packs/australia-hey-mate.webp.

const HAT_IDS: Array[String] = ["slouch", "slouch_gold", "slouch_ember"]
const SKIN_IDS: Array[String] = ["singlet"]
const FULL_BODY: Array[String] = []

const OLIVE := 0x6b7a3c


static func hat(id: String) -> Array:
	match id:
		"slouch": return _slouch(OLIVE, 0x3b2a18, 0xc89a5a, false)
		"slouch_gold":
			var p := _slouch(0x56622e, 0xf2c230, 0xf2c230, false)
			p.append(["hat", ["box", 0.12, 0.12, 0.03], 0xf2c230, [0, 0.12, 0.32], [0, 0, PI / 4]])
			return p
		"slouch_ember": return _slouch(0x2a2622, 0xff5a1f, 0xff7a1a, true)
	return []


## A wide-brimmed slouch hat with a band and five corks dangling on strings round the brim (`glow`: band and corks burn).
static func _slouch(brim: int, band: int, cork: int, glow: bool) -> Array:
	var g: Variant = {"glow": 0xff6a1a, "glow_k": 0.9}
	var p := [
		["hat", ["cyl", 0.55, 0.55, 0.035, 10], brim, [0, 0.0, 0]],
		["hat", ["cyl", 0.27, 0.31, 0.3, 8], brim, [0, 0.17, 0]],
		["hat", ["cyl", 0.315, 0.315, 0.07, 8], band, [0, 0.07, 0]] + ([[0, 0, 0], g] if glow else [])]
	for a: float in [0.0, 0.8, -0.8, 1.6, -1.6]:
		var x := 0.52 * sin(a)
		var z := 0.52 * cos(a)
		p.append(["hat", ["cyl", 0.008, 0.008, 0.16, 4], 0x2a2a2a, [x, -0.08, z]])
		p.append(["hat", ["cyl", 0.045, 0.04, 0.12, 6], cork, [x, -0.2, z]] + ([[0, 0, 0], g] if glow else []))
	return p


static func skin(id: String) -> Array:
	if id != "singlet":
		return []
	var p := [
		["body", ["cyl", PackKit.r_at(0.76) + 0.02, PackKit.r_at(0.14) + 0.02, 0.62, 6], 0xf7f7f2, [0, 0.45, 0]],   # white singlet over the torso
		["body", ["box", 0.09, 0.16, 0.05], 0xf7f7f2, [-0.17, 0.82, 0.3], [0, 0, 0]],                              # shoulder straps
		["body", ["box", 0.09, 0.16, 0.05], 0xf7f7f2, [0.17, 0.82, 0.3], [0, 0, 0]],
		["body", ["box", 0.09, 0.16, 0.05], 0xf7f7f2, [-0.17, 0.82, -0.3], [0, 0, 0]],
		["body", ["box", 0.09, 0.16, 0.05], 0xf7f7f2, [0.17, 0.82, -0.3], [0, 0, 0]]]
	for k in 2:
		p.append(["leg%d" % k, ["cyl", 0.175, 0.185, 0.42, 6], 0x2b4f8f, [0, -0.2, 0]])                            # stubbies
		p.append(["leg%d" % k, ["box", 0.31, 0.03, 0.46], 0xf2c230, [0, -0.815, 0.07]])                           # thong sole
		p.append(["leg%d" % k, ["box", 0.32, 0.035, 0.05], 0x1f8f4a, [0, -0.675, 0.1]])                           # strap across
		p.append(["leg%d" % k, ["box", 0.03, 0.14, 0.05], 0x1f8f4a, [-0.16, -0.74, 0.1]])
		p.append(["leg%d" % k, ["box", 0.03, 0.14, 0.05], 0x1f8f4a, [0.16, -0.74, 0.1]])
		p.append(["leg%d" % k, ["box", 0.04, 0.03, 0.18], 0x1f8f4a, [0, -0.675, 0.2]])
	return p
