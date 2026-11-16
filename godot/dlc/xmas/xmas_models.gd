class_name XmasModels
extends RefCounted
## "Ho Ho Ho" Xmas pack weapon models (godot/data/extra/xmas/weapons.json): LowPoly primitives, hand at the origin, business end along
## -Y, a gun's top is -Z. Colours follow docs/img/packs/xmas-ho-ho-ho.webp.

const KEYS: Array[String] = ["candycane", "snowballcannon", "giftbomb", "tinselwhip", "ornamentlauncher", "toymallet"]

const RED := 0xd7263d
const WHITE := 0xf7f7f7
const GREEN := 0x2e9a4a
const GOLD := 0xf2c230
const SNOW := 0xe6f4fb


static func build(key: String, b) -> bool:
	match key:
		"candycane": _candycane(b)
		"snowballcannon": _snowballcannon(b)
		"giftbomb": _giftbomb(b)
		"tinselwhip": _tinselwhip(b)
		"ornamentlauncher": _ornamentlauncher(b)
		"toymallet": _toymallet(b)
		_: return false
	return true


static func _candycane(b) -> void:            # red and white striped shaft with a hook at the business end (high-lift)
	var n := 8
	var seg := 2.1 / n
	for i in n:
		PackKit.cyl(b, 0.09, 0.09, seg, RED if i % 2 == 0 else WHITE, PackKit.V(0, 0.35 - (i + 0.5) * seg, 0), 6)
	PackKit.ball(b, 0.095, RED, PackKit.V(0, 0.35, 0))                                                # rounded butt
	var r := 0.4
	var cy := 0.35 - 2.1                                                                  # the hook's centre height: the shaft's end
	for k in 5:                                                                           # lower half-ring, striped in five pieces
		var a0 := PI + k * PI / 5.0
		PackKit.arc(b, r, 0.09, a0, a0 + PI / 5.0, RED if (4 - k) % 2 == 0 else WHITE, PackKit.V(-r, cy, 0), 3, 6)
	PackKit.ball(b, 0.095, WHITE if (4) % 2 == 0 else RED, PackKit.V(-2.0 * r, cy, 0))                # the hook's tip


static func _snowballcannon(b) -> void:       # a fat white tube with a green breech and muzzle, a wood drum and grip, and a heap of snowballs
	PackKit.cyl(b, 0.25, 0.25, 1.2, SNOW, PackKit.V(0, -0.75, 0), 10)                                 # barrel
	PackKit.cyl(b, 0.3, 0.3, 0.14, GREEN, PackKit.V(0, -1.35, 0), 10)                                 # muzzle ring
	PackKit.cyl(b, 0.21, 0.21, 0.03, 0x25404e, PackKit.V(0, -1.43, 0), 10)                            # the bore
	PackKit.cyl(b, 0.3, 0.3, 0.4, GREEN, PackKit.V(0, 0.0, 0), 10)                                    # breech
	PackKit.cyl(b, 0.26, 0.26, 0.07, SNOW, PackKit.V(0, 0.24, 0), 10)                                 # end cap
	PackKit.box(b, 0.13, 0.42, 0.2, 0x9a6a3a, PackKit.V(0, 0.15, 0.34), Vector3(-0.35, 0, 0))         # wooden grip
	PackKit.drum(b, 0.2, 0.34, 0x8a5a2b, PackKit.V(0, -0.62, 0.3), 8)                                 # the wooden drum under the barrel
	PackKit.box(b, 0.05, 0.16, 0.05, 0x2a2f36, PackKit.V(0, -0.15, 0.26))                             # trigger
	PackKit.ball(b, 0.28, 0xffffff, PackKit.V(0, -0.5, -0.22), Vector3(0.9, 1.9, 0.55))               # snow drift on top
	PackKit.ball(b, 0.17, 0xffffff, PackKit.V(0.02, -0.28, -0.4))                                     # snowballs
	PackKit.ball(b, 0.14, 0xf2fafe, PackKit.V(-0.04, -0.68, -0.38))
	PackKit.ball(b, 0.12, 0xffffff, PackKit.V(0.06, 0.0, -0.38))
	PackKit.tip(b, 0, -1.5, 0)


static func _giftbomb(b) -> void:             # a red present with green ribbon and bow and a lit fuse on top
	PackKit.box(b, 0.74, 0.6, 0.74, 0xc9252d, PackKit.V(0, -0.5, 0))                                  # the box
	PackKit.box(b, 0.82, 0.1, 0.82, 0xa81d26, PackKit.V(0, -0.22, 0))                                 # lid
	PackKit.box(b, 0.16, 0.62, 0.78, 0x1f8f4a, PackKit.V(0, -0.5, 0))                                 # ribbon one way
	PackKit.box(b, 0.78, 0.62, 0.16, 0x1f8f4a, PackKit.V(0, -0.5, 0))                                 # ... and the other
	PackKit.ball(b, 0.17, 0x23a655, PackKit.V(0.17, -0.12, 0), Vector3(1.4, 0.8, 0.8), Vector3(0, 0, 0.4))   # the bow
	PackKit.ball(b, 0.17, 0x23a655, PackKit.V(-0.17, -0.12, 0), Vector3(1.4, 0.8, 0.8), Vector3(0, 0, -0.4))
	PackKit.ball(b, 0.085, 0x1f8f4a, PackKit.V(0, -0.14, 0))
	PackKit.box(b, 0.07, 0.22, 0.03, 0x23a655, PackKit.V(0.09, -0.04, 0.15), Vector3(0.3, 0, 0.3))    # bow tails
	PackKit.cyl(b, 0.025, 0.025, 0.36, 0x3a2a1a, PackKit.V(0.05, 0.04, 0), 5, Vector3(0, 0, -0.3))    # the fuse
	PackKit.ball(b, 0.1, 0xff8a1f, PackKit.V(0.15, 0.24, 0))                                          # spark
	PackKit.ball(b, 0.06, 0xfff1a0, PackKit.V(0.15, 0.24, 0))
	PackKit.cone(b, 0.035, 0.14, 0xffd24a, PackKit.V(0.15, 0.4, 0), 4, true)                          # spark spikes
	PackKit.cone(b, 0.035, 0.14, 0xffd24a, PackKit.V(0.3, 0.26, 0), 4, true, Vector3(0, 0, -PI / 2))


static func _tinselwhip(b) -> void:           # a black grip wrapped in red and green tape with a long glittery tinsel lash and a gold tassel
	PackKit.cyl(b, 0.065, 0.07, 0.55, 0x3a2f2f, PackKit.V(0, -0.05, 0), 6)                            # grip
	for i in 3:
		PackKit.cyl(b, 0.082, 0.082, 0.07, RED if i % 2 == 0 else GREEN, PackKit.V(0, 0.1 - i * 0.15, 0), 6)
	PackKit.ball(b, 0.09, GOLD, PackKit.V(0, 0.27, 0))                                                # pommel
	var cols := [0xe83b4a, 0x23a655, 0xf4f7fa, 0xffd24a]
	var n := 13
	var prev := PackKit.V(0, -0.33, 0)
	for i in n:                                                                           # the lash: short links along an S curve
		var t := float(i + 1) / n
		var p := PackKit.V(sin(t * PI * 1.5) * 0.24 * (0.25 + t), -0.33 - t * 2.1, 0)
		PackKit.rod(b, lerpf(0.07, 0.03, t), prev, p, cols[i % 4], 5)
		if i % 3 == 1:
			PackKit.ball(b, 0.06, 0xfff6c8, p + PackKit.V(0.07, 0, 0.05))                            # glitter
		prev = p
	PackKit.cone(b, 0.07, 0.2, GOLD, prev + PackKit.V(0, -0.08, 0), 5)                                # tassel


static func _ornamentlauncher(b) -> void:     # a toy ray-gun in lilac steel: flared barrel with a gold ring, a hopper of baubles and a gold canister
	PackKit.box(b, 0.24, 0.6, 0.3, 0x7f88a8, PackKit.V(0, -0.15, 0))                                  # body
	PackKit.cyl(b, 0.14, 0.24, 0.8, 0x8e97b8, PackKit.V(0, -0.85, 0), 8)                              # flared barrel
	PackKit.cyl(b, 0.27, 0.27, 0.1, 0xd9a53a, PackKit.V(0, -1.28, 0), 8)                              # gold muzzle ring
	PackKit.cyl(b, 0.2, 0.2, 0.03, 0x2a2f45, PackKit.V(0, -1.35, 0), 8)                               # bore
	PackKit.cyl(b, 0.19, 0.19, 0.24, 0x6c7494, PackKit.V(0, -0.2, -0.27), 8)                          # bauble hopper on top
	PackKit.ball(b, 0.11, 0xe0303f, PackKit.V(0.08, -0.1, -0.42))                                     # baubles
	PackKit.ball(b, 0.11, 0x3b82f0, PackKit.V(-0.08, -0.26, -0.42))
	PackKit.ball(b, 0.1, 0x2fb858, PackKit.V(0.0, -0.38, -0.4))
	PackKit.ball(b, 0.1, 0xffd24a, PackKit.V(-0.02, 0.02, -0.42))
	PackKit.cyl(b, 0.11, 0.11, 0.44, 0xd9a53a, PackKit.V(0, -0.58, 0.24), 8)                          # gold canister under the barrel
	PackKit.box(b, 0.12, 0.36, 0.2, 0x5a6180, PackKit.V(0, 0.2, 0.2), Vector3(-0.3, 0, 0))            # grip
	PackKit.box(b, 0.04, 0.14, 0.04, 0xffd24a, PackKit.V(0, -0.02, 0.14))                             # trigger
	PackKit.tip(b, 0, -1.4, 0)


static func _toymallet(b) -> void:            # a candy-striped handle and a chunky toy-block head in green with red, yellow and blue bands
	for i in 5:
		PackKit.cyl(b, 0.07, 0.07, 0.28, RED if i % 2 == 0 else WHITE, PackKit.V(0, 0.06 - i * 0.28, 0), 6)
	PackKit.ball(b, 0.1, GOLD, PackKit.V(0, 0.22, 0))
	PackKit.drum(b, 0.36, 0.7, GREEN, PackKit.V(0, -1.55, 0), 10)                                     # the head
	PackKit.drum(b, 0.4, 0.16, RED, PackKit.V(-0.41, -1.55, 0), 10)
	PackKit.drum(b, 0.4, 0.16, RED, PackKit.V(0.41, -1.55, 0), 10)
	PackKit.drum(b, 0.38, 0.1, GOLD, PackKit.V(-0.2, -1.55, 0), 10)
	PackKit.drum(b, 0.38, 0.1, GOLD, PackKit.V(0.2, -1.55, 0), 10)
	PackKit.drum(b, 0.38, 0.1, 0x3b82f0, PackKit.V(0.0, -1.55, 0), 10)
	PackKit.drum(b, 0.34, 0.06, 0xdba763, PackKit.V(-0.52, -1.55, 0), 10)                             # wooden end caps
	PackKit.drum(b, 0.34, 0.06, 0xdba763, PackKit.V(0.52, -1.55, 0), 10)
