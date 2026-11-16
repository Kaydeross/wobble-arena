class_name XmasLooks
extends RefCounted
## "Ho Ho Ho" Xmas pack cosmetics: Santa Hat with a fluffy beard, Elf Cap, the Elf Tunic and the two Arcade victory hats
## (Normal: a gilded Santa hat; Nightmare: a Krampus hat with horns). Looks follow docs/img/packs/xmas-ho-ho-ho.webp.

const HAT_IDS: Array[String] = ["santabeard", "elfcap", "santa_gold", "santa_krampus"]
const SKIN_IDS: Array[String] = ["elftunic"]
const FULL_BODY: Array[String] = []

const RED := 0xd32f2f
const WHITE := 0xffffff
const GREEN := 0x2e9a4a


static func hat(id: String) -> Array:
	match id:
		"santabeard":
			var p := _santa(RED, WHITE, WHITE)
			p.append(["hat", ["ico", 0.09, 0], WHITE, [-0.09, -0.4, 0.33], [0, 0, 0.2], [1.5, 0.7, 0.9]])      # moustache
			p.append(["hat", ["ico", 0.09, 0], WHITE, [0.09, -0.4, 0.33], [0, 0, -0.2], [1.5, 0.7, 0.9]])
			p.append(["hat", ["ico", 0.2, 0], WHITE, [0, -0.68, 0.26], [0, 0, 0], [1.15, 1.5, 0.8]])           # the beard
			p.append(["hat", ["ico", 0.14, 0], WHITE, [-0.25, -0.5, 0.2], [0, 0, 0], [0.8, 1.3, 0.8]])
			p.append(["hat", ["ico", 0.14, 0], WHITE, [0.25, -0.5, 0.2], [0, 0, 0], [0.8, 1.3, 0.8]])
			return p
		"elfcap":
			return [
				["hat", ["cyl", 0.32, 0.32, 0.12, 8], WHITE, [0, 0.02, 0]],
				["hat", ["cyl", 0.325, 0.325, 0.04, 8], 0xd7263d, [0, 0.1, 0]],
				["hat", ["cone", 0.3, 0.7, 8], GREEN, [-0.12, 0.34, 0], [0, 0, 0.5]],
				["hat", ["ico", 0.08, 0], 0xffd24a, [-0.3, 0.66, 0]]]
		"santa_gold":                                           # a gilded Santa hat: gold cuff and pompom, a bell and a holly sprig
			var p := _santa(0xb71c1c, 0xf2c230, 0xf2c230)
			p.append(["hat", ["ico", 0.06, 0], 0xffe066, [0.0, -0.06, 0.34]])
			p.append(["hat", ["box", 0.1, 0.03, 0.03], 0x2e9a4a, [0.12, 0.06, 0.34], [0, 0, 0.5]])
			p.append(["hat", ["ico", 0.035, 0], 0xd7263d, [0.18, 0.04, 0.35]])
			return p
		"santa_krampus":                                        # Krampus: a black-red hat, grey fur, two dark horns and a glowing red gem
			var p := _santa(0x4a0f14, 0x8a8a92, 0x8a8a92)
			p.append(["hat", ["cone", 0.07, 0.42, 5], 0x1a1a1a, [-0.34, 0.14, 0], [0, 0, 0.7]])
			p.append(["hat", ["cone", 0.07, 0.42, 5], 0x1a1a1a, [0.34, 0.14, 0], [0, 0, -0.7]])
			p.append(["hat", ["ico", 0.065, 0], 0xff2a2a, [0, 0.03, 0.35], [0, 0, 0], {"glow": 0xff2a2a, "glow_k": 0.9}])
			return p
	return []


static func _santa(cone: int, cuff: int, pom: int) -> Array:    # cone hat drooping to one side, a cuff and a pompom at the tip
	return [
		["hat", ["cone", 0.32, 0.65, 8], cone, [-0.05, 0.3, 0], [0, 0, 0.3]],
		["hat", ["cyl", 0.34, 0.34, 0.14, 8], cuff, [0, 0.02, 0]],
		["hat", ["ico", 0.1, 0], pom, [-0.147, 0.61, 0]]]


static func skin(id: String) -> Array:
	if id != "elftunic":
		return []
	var p := [
		["body", ["cyl", 0.43, 0.46, 0.24, 6], GREEN, [0, 0.07, 0]],                       # tunic skirt
		["body", ["cyl", 0.465, 0.47, 0.06, 6], 0xd7263d, [0, -0.04, 0]],                  # red hem
		["body", ["tor", 0.3, 0.07, 4, 6], WHITE, [0, 0.9, 0], [PI / 2, 0, 0]],            # white collar
		["body", ["ico", 0.04, 0], 0xf2c230, [0, 0.62, PackKit.r_at(0.62) + 0.02]],         # gold buttons
		["body", ["ico", 0.04, 0], 0xf2c230, [0, 0.46, PackKit.r_at(0.46) + 0.02]]]
	for sx: float in [-1.0, 1.0]:
		p.append(["neck", ["cone", 0.07, 0.34, 4], 0xffe0b3, [sx * 0.46, 0.4, 0], [0, 0, -sx * 1.07]])       # pointy ears
	for k in 2:
		p.append(["leg%d" % k, ["cone", 0.07, 0.26, 5], GREEN, [0, -0.71, 0.37], [1.0, 0, 0]])             # curly shoe tips
		p.append(["leg%d" % k, ["ico", 0.045, 0], 0xffd24a, [0, -0.6, 0.5]])                                  # with a bell
	return p
