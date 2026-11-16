class_name KitchenLooks
extends RefCounted
## "On Fire" Kitchen pack cosmetics: Chef Toque, the stained Apron, the Dishie Bot look and the two Arcade victory toques
## (Normal: gold-banded Head Chef; Nightmare: a charred toque with flames). Looks follow docs/img/packs/kitchen-on-fire.webp.

const HAT_IDS: Array[String] = ["toque", "toque_gold", "toque_inferno"]
const SKIN_IDS: Array[String] = ["apron", "dishiebot"]
const FULL_BODY: Array[String] = ["dishiebot"]

const CREAM := 0xf0e6cf
const STEEL := 0xb8c3cc
const STEEL2 := 0x9aa7b2
const DARK := 0x2a323a


static func hat(id: String) -> Array:
	match id:
		"toque":
			return _toque(0xffffff, 0xdcdcdc, 0xf4f4f4)
		"toque_gold":                                          # Head Chef: gold band, gold top disc and a gold badge
			var p := _toque(0xffffff, 0xdcdcdc, 0xf2c230)
			p.append(["hat", ["cyl", 0.3, 0.3, 0.03, 12], 0xf2c230, [0, 0.47, 0]])
			p.append(["hat", ["box", 0.14, 0.14, 0.03], 0xf2c230, [0, 0.03, 0.31], [0, 0, PI / 4]])
			return p
		"toque_inferno":                                       # charred toque with a glowing ember band and flames on top
			var p := _toque(0x2a2d33, 0x1d1f23, 0x23262b)
			p[0][2] = 0xff5a1f
			p[0].append([0, 0, 0])
			p[0].append({"glow": 0xff5a1f, "glow_k": 0.9})
			p.append(["hat", ["cone", 0.1, 0.4, 5], 0xff7a1a, [0.0, 1.06, 0.0], [0, 0, 0], {"glow": 0xff7a1a, "glow_k": 0.9}])
			p.append(["hat", ["cone", 0.08, 0.3, 5], 0xffa02e, [0.18, 1.0, 0.04], [0, 0, -0.4], {"glow": 0xffa02e, "glow_k": 0.9}])
			p.append(["hat", ["cone", 0.08, 0.28, 5], 0xffa02e, [-0.18, 1.0, -0.04], [0, 0, 0.4], {"glow": 0xffa02e, "glow_k": 0.9}])
			return p
	return []


static func _toque(body: int, pleat: int, band: int) -> Array:   # a tall pleated chef's hat: band, a pleated column, a flared top with a flat crown
	var p := [
		["hat", ["cyl", 0.3, 0.28, 0.2, 10], band, [0, 0.02, 0]],
		["hat", ["cyl", 0.3, 0.3, 0.45, 12], body, [0, 0.33, 0]],
		["hat", ["cyl", 0.43, 0.3, 0.3, 12], body, [0, 0.69, 0]],
		["hat", ["cyl", 0.43, 0.43, 0.03, 12], pleat, [0, 0.855, 0]]]
	for x: float in [-0.12, 0.0, 0.12]:
		p.append(["hat", ["box", 0.025, 0.42, 0.03], pleat, [x, 0.34, 0.305 - absf(x) * 0.3]])
	return p


static func skin(id: String) -> Array:
	match id:
		"apron": return _apron()
		"dishiebot": return _dishie()
	return []


static func _apron() -> Array:                                  # a cream apron over a white shirt, shoulder straps, back ties and a lot of stains
	var p := []
	PackKit.faces(p, 0.62, 0.3, 0.4, 0.04, CREAM, 0.03)         # bib
	PackKit.faces(p, 0.22, 0.3, 0.38, 0.04, CREAM, 0.03)        # skirt
	for sg: float in [-1.0, 1.0]:
		p.append(["body", ["box", 0.06, 0.04, 0.72], CREAM, [sg * 0.17, 0.865, 0.0]])
		p.append(["body", ["box", 0.07, 0.3, 0.03], CREAM, [sg * 0.07, 0.06, -0.36], [0.25, 0, sg * 0.3]])
	p.append(["body", ["box", 0.2, 0.15, 0.03], 0xd9ccb2, [0, 0.3, PackKit.r_at(0.3) + 0.06]])   # pocket
	for s: Array in [[1.0, 0.66, 0.05, 0.09, 0.07, 0x8a4a22], [-1.0, 0.7, -0.06, 0.07, 0.1, 0xb0561f],
			[1.0, 0.28, 0.0, 0.14, 0.1, 0x7a3b18], [-1.0, 0.22, 0.06, 0.1, 0.07, 0xc9a227],
			[-1.0, 0.36, -0.07, 0.06, 0.06, 0x9a2f22], [1.0, 0.16, -0.08, 0.08, 0.06, 0x9a2f22]]:
		PackKit.patch(p, s[0], s[1], s[2], s[3], s[4], s[5])
	return p


static func _dishie() -> Array:                                 # The Dishie Bot: a riveted steel capsule, a glowing visor, scrubbing brushes for hands
	var p := [
		["body", ["cyl", 0.36, 0.4, 0.38, 12], STEEL2, [0, 0.19, 0]],
		["body", ["cyl", 0.42, 0.36, 0.5, 12], STEEL, [0, 0.62, 0]],
		["body", ["cyl", 0.42, 0.42, 0.46, 12], STEEL, [0, 1.1, 0]],
		["body", ["ico", 0.42, 1], STEEL, [0, 1.33, 0], [0, 0, 0], [1, 0.55, 1]],
		["body", ["tor", 0.425, 0.025, 4, 12], STEEL2, [0, 0.87, 0], [PI / 2, 0, 0]],       # seams
		["body", ["tor", 0.4, 0.025, 4, 12], STEEL2, [0, 0.38, 0], [PI / 2, 0, 0]],
		["body", ["box", 0.58, 0.28, 0.1], DARK, [0, 1.1, 0.4]],                            # visor
		["body", ["box", 0.1, 0.12, 0.03], 0x39e0ff, [-0.12, 1.1, 0.455], [0, 0, 0], {"glow": 0x39e0ff, "glow_k": 0.9}],
		["body", ["box", 0.1, 0.12, 0.03], 0x39e0ff, [0.12, 1.1, 0.455], [0, 0, 0], {"glow": 0x39e0ff, "glow_k": 0.9}],
		["body", ["box", 0.3, 0.26, 0.05], 0x7f8d99, [0, 0.62, 0.4]],                       # chest panel
		["body", ["ico", 0.035, 0], 0xe3403b, [-0.07, 0.66, 0.44]],
		["body", ["ico", 0.035, 0], 0x3fd070, [0.07, 0.66, 0.44]],
		["body", ["cyl", 0.015, 0.015, 0.2, 4], DARK, [0, 1.6, 0]],                         # antenna
		["body", ["ico", 0.05, 0], 0xff5a5a, [0, 1.72, 0]]]
	for sx: float in [-1.0, 1.0]:
		p.append(["body", ["cyl", 0.07, 0.07, 0.1, 6], STEEL2, [sx * 0.44, 1.1, 0], [0, 0, PI / 2]])   # side bolts
	for a in ["armL", "arm"]:                                                              # scrubbing brushes
		p.append([a, ["box", 0.34, 0.12, 0.24], 0x3b6fc0, [0, -0.93, 0]])
		p.append([a, ["box", 0.3, 0.1, 0.2], 0xe8c46a, [0, -1.02, 0]])
	return p
