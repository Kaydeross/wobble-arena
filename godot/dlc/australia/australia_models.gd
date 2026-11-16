class_name AustraliaModels
extends RefCounted
## "Hey Mate" Australia pack weapon models (godot/data/extra/australia/weapons.json): LowPoly primitives, hand at the origin,
## business end along -Y, a gun's top is -Z. Colours follow docs/img/packs/australia-hey-mate.webp.
## (The shared weapon set already has a "boomerang", so the pack's weapon id is "aussieboomerang".)

const KEYS: Array[String] = ["cricketbat", "aussieboomerang", "thongslapper", "vegemitejar", "bbqtongs", "didgeridooblaster"]

const STEEL := 0xaeb8c0
const STEEL_D := 0x87919a


static func build(key: String, b) -> bool:
	match key:
		"cricketbat": _cricketbat(b)
		"aussieboomerang": _aussieboomerang(b)
		"thongslapper": _thongslapper(b)
		"vegemitejar": _vegemitejar(b)
		"bbqtongs": _bbqtongs(b)
		"didgeridooblaster": _didgeridooblaster(b)
		_: return false
	return true


static func _cricketbat(b) -> void:           # English-willow blade with a raised spine, a cane handle and a green rubber grip
	PackKit.cyl(b, 0.065, 0.065, 0.5, 0x2f6b3f, PackKit.V(0, -0.05, 0), 6)                            # grip
	for y in [0.08, -0.06, -0.2]:
		PackKit.cyl(b, 0.072, 0.072, 0.035, 0x1d3f27, PackKit.V(0, y, 0), 6)                          # grip bands
	PackKit.cyl(b, 0.078, 0.078, 0.05, 0x1d1d1d, PackKit.V(0, 0.22, 0), 6)                            # top cap
	PackKit.cyl(b, 0.055, 0.06, 0.42, 0xb78a4c, PackKit.V(0, -0.52, 0), 6)                            # cane handle
	PackKit.box(b, 0.17, 0.26, 0.085, 0xe3be82, PackKit.V(0, -0.8, 0))                                # shoulder
	PackKit.box(b, 0.32, 0.2, 0.095, 0xe3be82, PackKit.V(0, -0.98, 0))
	PackKit.box(b, 0.42, 1.1, 0.1, 0xe9c78f, PackKit.V(0, -1.63, 0))                                  # the blade
	PackKit.box(b, 0.18, 1.12, 0.05, 0xd1a468, PackKit.V(0, -1.6, -0.07))                            # spine ridge on the back
	PackKit.box(b, 0.43, 0.05, 0.12, 0xc99a58, PackKit.V(0, -2.2, 0))                                 # toe
	PackKit.box(b, 0.26, 0.28, 0.014, 0xd7263d, PackKit.V(0, -1.5, 0.057))                           # maker's sticker
	PackKit.box(b, 0.22, 0.045, 0.016, 0xffffff, PackKit.V(0, -1.5, 0.058))


static func _aussieboomerang(b) -> void:          # a chunky red-brown boomerang with a cream painted band and dots, flat in the XY plane, tip forward
	var n := 5
	for sg in [-1.0, 1.0]:
		for i in n:
			var t := (i + 0.5) / n
			var a := Vector3(sg * (0.78 * i / n), -0.95 + 0.62 * pow(i / float(n), 1.5), 0)
			var c := Vector3(sg * (0.78 * (i + 1) / n), -0.95 + 0.62 * pow((i + 1) / float(n), 1.5), 0)
			var w := lerpf(0.24, 0.13, t)
			var col := 0xb5532b if i % 2 == 0 else 0xa14822
			var m: MeshInstance3D = PackKit.box(b, 0.1, 0.1, 0.05, col, (a + c) * 0.5)
			var d := c - a
			m.mesh = LowPoly.box(d.length() * 1.12, w, 0.06)
			m.transform = Transform3D(Basis(Vector3.BACK, atan2(d.y, d.x)), (a + c) * 0.5)
	PackKit.cyl(b, 0.2, 0.2, 0.06, 0xb5532b, PackKit.V(0, -0.95, 0), 6, Vector3(PI / 2, 0, 0))        # the elbow
	PackKit.box(b, 0.1, 0.2, 0.075, 0xf0d9a0, PackKit.V(0.17, -0.9, 0), Vector3(0, 0, 0.9))           # cream painted stripes
	PackKit.box(b, 0.1, 0.2, 0.075, 0xf0d9a0, PackKit.V(-0.17, -0.9, 0), Vector3(0, 0, -0.9))
	for sg in [-1.0, 1.0]:
		PackKit.ball(b, 0.035, 0xf0d9a0, PackKit.V(sg * 0.5, -0.78, 0.04))                            # dots
		PackKit.ball(b, 0.03, 0xf0d9a0, PackKit.V(sg * 0.68, -0.63, 0.04))
	PackKit.cyl(b, 0.04, 0.04, 0.95, 0x6a4a2a, PackKit.V(0, -0.47, 0), 5)                             # a short wrapped grip up to the hand


static func _thongslapper(b) -> void:         # a giant flip-flop held by the heel: tan sole, dark underside, green Y strap
	var tan := 0xe8c98e
	var dk := 0xa87a3e
	PackKit.disc(b, 0.27, 0.07, tan, PackKit.V(0, -0.36, 0), 10, Vector3(1, 1, 1.25))                 # heel pad
	PackKit.box(b, 0.4, 0.5, 0.07, tan, PackKit.V(0, -0.72, 0))                                       # arch
	PackKit.disc(b, 0.35, 0.07, tan, PackKit.V(0, -1.12, 0), 10, Vector3(1, 1, 1.4))                  # forefoot pad
	PackKit.disc(b, 0.28, 0.05, dk, PackKit.V(0, -0.36, -0.06), 10, Vector3(1, 1, 1.28))              # darker underside
	PackKit.box(b, 0.42, 0.5, 0.05, dk, PackKit.V(0, -0.72, -0.06))
	PackKit.disc(b, 0.36, 0.05, dk, PackKit.V(0, -1.12, -0.06), 10, Vector3(1, 1, 1.43))
	PackKit.cyl(b, 0.045, 0.045, 0.14, 0x23a655, PackKit.V(0, -0.62, 0.07), 5, Vector3(PI / 2, 0, 0))   # the toe post
	PackKit.box(b, 0.07, 0.46, 0.045, 0x23a655, PackKit.V(0.16, -0.46, 0.09), Vector3(0, 0, -0.75))   # the Y strap
	PackKit.box(b, 0.07, 0.46, 0.045, 0x23a655, PackKit.V(-0.16, -0.46, 0.09), Vector3(0, 0, 0.75))
	PackKit.box(b, 0.3, 0.03, 0.02, 0xf2c230, PackKit.V(0, -1.12, 0.045))                             # a go-faster stripe
	PackKit.box(b, 0.2, 0.025, 0.02, dk, PackKit.V(0, -0.2, 0.045))                                   # heel grip marks
	PackKit.box(b, 0.2, 0.025, 0.02, dk, PackKit.V(0, -0.3, 0.045))


static func _vegemitejar(b) -> void:          # the glass jar of black spread: red lid, yellow label with a red badge, lobbed by the lid
	PackKit.cyl(b, 0.27, 0.27, 0.16, 0xd4262a, PackKit.V(0, -0.12, 0), 10)                            # lid
	PackKit.cyl(b, 0.285, 0.285, 0.04, 0xa81d22, PackKit.V(0, -0.12, 0), 10)                          # its ridge
	PackKit.cyl(b, 0.25, 0.25, 0.06, 0x1d1008, PackKit.V(0, -0.23, 0), 10)                            # neck
	PackKit.cyl(b, 0.25, 0.32, 0.1, 0x2a1608, PackKit.V(0, -0.31, 0), 10)                             # shoulder
	PackKit.cyl(b, 0.32, 0.32, 0.55, 0x2a1608, PackKit.V(0, -0.64, 0), 10)                            # the jar
	PackKit.cyl(b, 0.335, 0.335, 0.3, 0xf7c914, PackKit.V(0, -0.64, 0), 10)                           # yellow label
	PackKit.box(b, 0.3, 0.13, 0.04, 0xc0141c, PackKit.V(0, -0.64, 0.335))                             # red badge
	PackKit.box(b, 0.24, 0.04, 0.045, 0xffffff, PackKit.V(0, -0.64, 0.338))                           # the name, roughly
	PackKit.cyl(b, 0.3, 0.32, 0.05, 0x1d1008, PackKit.V(0, -0.94, 0), 10)                             # base


static func _bbqtongs(b) -> void:             # stainless tongs: a spring ring, two arms with green grips and toothed paddles
	b.mi(null, LowPoly.torus(0.11, 0.028, 4, 8, PI * 1.5), STEEL_D, PackKit.V(0, 0.04, 0), Vector3(0, 0, -PI / 4))   # the spring ring
	for sg in [-1.0, 1.0]:
		PackKit.box(b, 0.085, 0.81, 0.06, STEEL, PackKit.V(sg * 0.1, -0.4, 0), Vector3(0, 0, sg * -0.148))        # upper arm, splayed
		PackKit.box(b, 0.12, 0.55, 0.095, 0x2f7f5a, PackKit.V(sg * 0.1, -0.4, 0), Vector3(0, 0, sg * -0.148))      # green grip
		PackKit.box(b, 0.08, 1.06, 0.055, STEEL, PackKit.V(sg * 0.105, -1.32, 0), Vector3(0, 0, sg * 0.105))      # lower arm, converging
		PackKit.box(b, 0.11, 0.32, 0.05, STEEL_D, PackKit.V(sg * 0.06, -1.9, 0))                                  # paddle
		for k in 2:
			PackKit.box(b, 0.05, 0.04, 0.055, STEEL, PackKit.V(sg * 0.02, -2.0 - k * 0.1, 0))                       # teeth on the inside edge
	PackKit.box(b, 0.3, 0.04, 0.04, STEEL_D, PackKit.V(0, -0.82, 0))                                  # the cross pin between the arms


static func _didgeridooblaster(b) -> void:    # a long wooden horn bolted to a green receiver and pistol grip, bell mouth at the front
	PackKit.cyl(b, 0.13, 0.17, 1.7, 0xc07a3d, PackKit.V(0, -1.15, 0), 8)                              # the horn
	PackKit.cyl(b, 0.17, 0.28, 0.3, 0x8a4a22, PackKit.V(0, -2.12, 0), 8)                              # bell mouth
	PackKit.cyl(b, 0.22, 0.22, 0.02, 0x2a1608, PackKit.V(0, -2.28, 0), 8)                             # bore
	for i in 3:
		PackKit.cyl(b, 0.165, 0.165, 0.07, 0xf0e1b8 if i % 2 == 0 else 0xb33a2a, PackKit.V(0, -0.85 - i * 0.25, 0), 8)   # plain stripes
	PackKit.box(b, 0.26, 0.55, 0.3, 0x3f9a62, PackKit.V(0, -0.05, 0))                                 # receiver
	PackKit.box(b, 0.12, 0.42, 0.08, 0x2a6e44, PackKit.V(0, -0.05, -0.18))                            # top rail
	PackKit.cyl(b, 0.2, 0.2, 0.1, 0x2a6e44, PackKit.V(0, -0.38, 0), 8)                                # collar to the horn
	PackKit.cyl(b, 0.09, 0.13, 0.3, 0x6a3a1c, PackKit.V(0, 0.38, 0), 8)                               # mouthpiece
	PackKit.box(b, 0.12, 0.34, 0.2, 0x2a3640, PackKit.V(0, 0.12, 0.24), Vector3(-0.3, 0, 0))          # pistol grip
	PackKit.box(b, 0.04, 0.14, 0.04, 0xffd24a, PackKit.V(0, -0.1, 0.16))                              # trigger
	PackKit.tip(b, 0, -2.35, 0)
