class_name KitchenModels
extends RefCounted
## "On Fire" Kitchen pack weapon models (godot/data/extra/kitchen/weapons.json): built from LowPoly primitives, same convention as
## WeaponModels (the hand is the origin, the business end points along -Y, a gun's top is -Z). Colours follow docs/img/packs/kitchen-on-fire.webp.

const KEYS: Array[String] = ["fryingpan", "cleaver", "flambetorch", "rollingpin", "peppergrinder", "souppot"]

const STEEL := 0xb8c2c9
const STEEL_L := 0xdfe6ec
const STEEL_D := 0x8a949c
const IRON := 0x3b3f46
const BLACK := 0x23262b


## true when `key` is a Kitchen weapon (and its parts are now in `b.root`).
static func build(key: String, b) -> bool:
	match key:
		"fryingpan": _fryingpan(b)
		"cleaver": _cleaver(b)
		"flambetorch": _flambetorch(b)
		"rollingpin": _rollingpin(b)
		"peppergrinder": _peppergrinder(b)
		"souppot": _souppot(b)
		_: return false
	return true


static func _fryingpan(b) -> void:            # cast-iron pan: a long black handle, a flared wall, a bright rim and a dark cooking face
	PackKit.cyl(b, 0.055, 0.05, 0.86, 0x2a2c31, PackKit.V(0, -0.33, 0), 6)                           # handle
	PackKit.cyl(b, 0.07, 0.07, 0.06, STEEL_D, PackKit.V(0, 0.12, 0), 6)                               # hanging cap
	PackKit.box(b, 0.17, 0.22, 0.08, 0x5a6068, PackKit.V(0, -0.82, 0))                                # the neck that carries the handle
	PackKit.box(b, 0.05, 0.05, 0.1, STEEL_L, PackKit.V(0.0, -0.76, 0))                                # rivet
	PackKit.disc(b, 0.58, 0.14, IRON, PackKit.V(0, -1.45, 0), 12)                                     # pan wall
	PackKit.disc(b, 0.63, 0.04, STEEL_D, PackKit.V(0, -1.45, 0.075), 12)                              # rim, front
	PackKit.disc(b, 0.63, 0.04, STEEL_D, PackKit.V(0, -1.45, -0.075), 12)                             # rim, back
	PackKit.disc(b, 0.53, 0.03, 0x17191c, PackKit.V(0, -1.45, 0.1), 12)                               # the black cooking face
	PackKit.box(b, 0.1, 0.04, 0.06, STEEL_L, PackKit.V(0.0, -2.07, 0.0))                              # a glint on the rim
	PackKit.disc(b, 0.12, 0.02, 0x2d3036, PackKit.V(0, -1.45, 0.12), 8)                               # a worn spot


static func _cleaver(b) -> void:              # butcher's cleaver: wood handle with brass rivets, a wide steel slab with a hanging hole
	PackKit.box(b, 0.1, 0.62, 0.15, 0x6b3f1f, PackKit.V(0, -0.15, 0))                                 # handle
	for y in [-0.02, -0.17, -0.32]:
		PackKit.box(b, 0.04, 0.045, 0.18, 0xe3c35a, PackKit.V(0, y, 0))                               # brass rivets through it
	PackKit.box(b, 0.13, 0.07, 0.17, STEEL_D, PackKit.V(0, -0.5, 0))                                  # bolster
	PackKit.box(b, 0.58, 0.86, 0.045, 0xcfd6dd, PackKit.V(0.2, -0.97, 0))                             # blade
	PackKit.box(b, 0.07, 0.86, 0.08, STEEL_D, PackKit.V(-0.065, -0.97, 0))                            # thick spine
	PackKit.box(b, 0.05, 0.86, 0.055, 0xf6fafc, PackKit.V(0.5, -0.97, 0))                             # bright edge
	PackKit.box(b, 0.11, 0.09, 0.06, BLACK, PackKit.V(0.3, -0.7, 0))                                  # hanging hole
	PackKit.box(b, 0.4, 0.04, 0.05, STEEL_L, PackKit.V(0.2, -0.58, 0.0))                              # top bevel


static func _flambetorch(b) -> void:          # a cooking torch: orange gas bottle in the fist, a brass burner and a three-layer flame
	PackKit.cyl(b, 0.19, 0.19, 0.8, 0xe0502a, PackKit.V(0, -0.05, 0), 8)                              # the bottle
	PackKit.cyl(b, 0.197, 0.197, 0.2, 0xf5e6c8, PackKit.V(0, 0.16, 0), 8)                             # label
	PackKit.cyl(b, 0.197, 0.197, 0.07, STEEL, PackKit.V(0, -0.3, 0), 8)                               # band
	PackKit.cyl(b, 0.1, 0.19, 0.1, 0xe0502a, PackKit.V(0, 0.4, 0), 8)                                 # shoulder
	PackKit.cyl(b, 0.06, 0.06, 0.05, BLACK, PackKit.V(0, 0.48, 0), 6)                                 # valve wheel
	PackKit.cyl(b, 0.09, 0.19, 0.12, 0xc9421f, PackKit.V(0, -0.46, 0), 8)                             # neck of the bottle
	PackKit.box(b, 0.13, 0.1, 0.13, STEEL_D, PackKit.V(0, -0.58, 0))                                  # valve block
	PackKit.cyl(b, 0.045, 0.05, 0.4, STEEL, PackKit.V(0, -0.82, 0), 6)                                # nozzle tube
	PackKit.cyl(b, 0.12, 0.07, 0.16, 0xb86a3a, PackKit.V(0, -1.08, 0), 8)                             # brass burner
	PackKit.cyl(b, 0.135, 0.135, 0.03, 0x7a4426, PackKit.V(0, -1.18, 0), 8)
	PackKit.ball(b, 0.2, 0xff5a1f, PackKit.V(0, -1.5, 0), Vector3(1, 2.0, 1))               # flame, outer
	PackKit.cone(b, 0.13, 0.55, 0xff5a1f, PackKit.V(0, -2.08, 0), 6)
	PackKit.ball(b, 0.14, 0xffa02e, PackKit.V(0, -1.46, 0), Vector3(1, 1.9, 1))            # middle
	PackKit.cone(b, 0.08, 0.4, 0xffa02e, PackKit.V(0, -1.95, 0), 5)
	PackKit.ball(b, 0.08, 0xfff1a0, PackKit.V(0, -1.36, 0), Vector3(1, 1.8, 1))            # hot core
	PackKit.ball(b, 0.06, 0xff7a1f, PackKit.V(0.17, -1.55, 0.05), Vector3(1, 1.6, 1))      # a lick of flame to the side
	PackKit.box(b, 0.07, 0.09, 0.07, 0xc0392b, PackKit.V(0, 0.25, 0.2))                               # ignition button
	PackKit.tip(b, 0, -2.35, 0)


static func _rollingpin(b) -> void:           # a wooden rolling pin with two turned handles and two darker bands
	PackKit.cyl(b, 0.065, 0.065, 0.42, 0xb9863f, PackKit.V(0, 0.0, 0), 6)                             # the handle in the fist
	PackKit.cyl(b, 0.09, 0.09, 0.06, 0xa87638, PackKit.V(0, 0.22, 0), 6)                              # end knob
	PackKit.cyl(b, 0.07, 0.19, 0.1, 0xdcab62, PackKit.V(0, -0.3, 0), 8)                               # shoulder
	PackKit.cyl(b, 0.19, 0.19, 1.0, 0xdcab62, PackKit.V(0, -0.85, 0), 8)                              # the barrel
	PackKit.cyl(b, 0.195, 0.195, 0.04, 0xb07a38, PackKit.V(0, -0.55, 0), 8)                           # bands
	PackKit.cyl(b, 0.195, 0.195, 0.04, 0xb07a38, PackKit.V(0, -1.15, 0), 8)
	PackKit.cyl(b, 0.19, 0.07, 0.1, 0xdcab62, PackKit.V(0, -1.4, 0), 8)
	PackKit.cyl(b, 0.065, 0.065, 0.42, 0xb9863f, PackKit.V(0, -1.66, 0), 6)                           # far handle
	PackKit.cyl(b, 0.09, 0.09, 0.06, 0xa87638, PackKit.V(0, -1.9, 0), 6)
	PackKit.box(b, 0.1, 0.5, 0.03, 0xf2d9a0, PackKit.V(0.0, -0.85, 0.185))                            # a highlight along the barrel


static func _peppergrinder(b) -> void:        # a turned dark-wood pepper mill held like a pistol, spraying peppercorns from its base
	PackKit.ball(b, 0.11, 0x3a1e10, PackKit.V(0, 0.4, 0))                                             # the knob
	PackKit.cyl(b, 0.09, 0.12, 0.14, 0x4a2616, PackKit.V(0, 0.26, 0), 8)                              # top cap
	PackKit.cyl(b, 0.12, 0.145, 0.36, 0x6a3a22, PackKit.V(0, 0.02, 0), 8)                             # upper body
	PackKit.cyl(b, 0.125, 0.125, 0.1, 0xd9b24a, PackKit.V(0, -0.22, 0), 8)                            # brass waist
	PackKit.cyl(b, 0.13, 0.2, 0.6, 0x6a3a22, PackKit.V(0, -0.57, 0), 8)                               # lower body widens
	PackKit.cyl(b, 0.2, 0.24, 0.13, 0x3a1e10, PackKit.V(0, -0.95, 0), 8)                              # foot, the muzzle
	PackKit.cyl(b, 0.15, 0.15, 0.03, 0x1b1b1d, PackKit.V(0, -1.03, 0), 8)                             # grinder hole
	PackKit.box(b, 0.1, 0.3, 0.17, 0x2a2f36, PackKit.V(0, 0.12, 0.22), Vector3(-0.3, 0, 0))           # pistol grip
	PackKit.box(b, 0.04, 0.14, 0.04, 0xc0392b, PackKit.V(0, -0.02, 0.12))                             # trigger
	PackKit.ball(b, 0.04, 0x1b1b1d, PackKit.V(0.06, -1.2, 0.04))                                      # spicy peppercorns
	PackKit.ball(b, 0.035, 0x1b1b1d, PackKit.V(-0.07, -1.32, -0.03))
	PackKit.ball(b, 0.04, 0x1b1b1d, PackKit.V(0.02, -1.45, 0.06))
	PackKit.tip(b, 0, -1.5, 0)


static func _souppot(b) -> void:              # a steel stockpot of bubbling orange soup, carried by its wire bail
	PackKit.cyl(b, 0.42, 0.38, 0.6, STEEL, PackKit.V(0, -0.7, 0), 10)                                 # the pot
	PackKit.cyl(b, 0.45, 0.45, 0.05, STEEL_L, PackKit.V(0, -0.4, 0), 10)                              # rolled rim
	PackKit.cyl(b, 0.38, 0.38, 0.05, 0xdf5a1c, PackKit.V(0, -0.35, 0), 10)                            # the soup
	PackKit.ball(b, 0.08, 0xf08a3c, PackKit.V(0.12, -0.3, 0.08))                                      # bubbles
	PackKit.ball(b, 0.06, 0xf08a3c, PackKit.V(-0.16, -0.3, -0.1))
	PackKit.box(b, 0.07, 0.3, 0.04, 0xdf5a1c, PackKit.V(0.16, -0.55, 0.42))                           # drips down the front
	PackKit.box(b, 0.07, 0.18, 0.04, 0xdf5a1c, PackKit.V(-0.14, -0.49, 0.42))
	PackKit.box(b, 0.16, 0.07, 0.1, 0x4a4f55, PackKit.V(0.5, -0.55, 0))                               # side handles
	PackKit.box(b, 0.16, 0.07, 0.1, 0x4a4f55, PackKit.V(-0.5, -0.55, 0))
	b.mi(null, LowPoly.torus(0.42, 0.03, 4, 10, PI), 0x2a2f36, PackKit.V(0, -0.4, 0))           # the bail handle
	PackKit.box(b, 0.05, 0.06, 0.03, 0xe8eef3, PackKit.V(0.16, -0.12, 0.0))                           # a wisp of steam
	PackKit.box(b, 0.04, 0.06, 0.03, 0xe8eef3, PackKit.V(0.2, -0.04, 0.0))
