class_name ClassStats
extends RefCounted
## The class parameters the Character page shows as bars (ui/setup_wizard.gd). Each bar is one class multiplier
## (shared/classes.json + data/extra/classes.json; the Wobbler is 1.0 in all of them) mapped to 0..1 between a
## sensible floor and ceiling, so the baseline sits near the middle and the extremes (Gramps' slow feet, Bulwark's
## health, Zippy's speed) use the whole bar. A longer bar is always better: KB resist is -log2(kb), because the class
## `kb` multiplier is how far you are launched (Scamp 1.3 flies far, Bulwark 0.5 hardly moves).
## Pure data (no autoloads: tests load it before they start). Display only: combat reads the multipliers directly.

## [label, class key, floor, ceiling, invert (bar = -log2 of the multiplier)]
const STATS := [
	["Speed", "spd", 0.75, 1.35, false],
	["Jump", "jump", 0.8, 1.35, false],
	["Health", "hp", 0.65, 1.5, false],
	["Damage", "dmg", 0.85, 1.25, false],
	["Fire rate", "rate", 0.85, 1.25, false],
	["KB resist", "kb", -0.5, 1.0, true],
]
const MIN_BAR := 0.07       ## a floor so the weakest value still shows a sliver of bar

## 0..1 for one stat of a class record (`norm(stat, {})` is the Wobbler baseline).
static func norm(stat: Array, c: Dictionary) -> float:
	var v := float(c.get(stat[1], 1.0))
	if stat[4]: v = -log(maxf(v, 0.05)) / log(2.0)
	return clampf((v - float(stat[2])) / (float(stat[3]) - float(stat[2])), MIN_BAR, 1.0)

## [[label, 0..1, 0..1 of the Wobbler], ...] for a class record `c` (the third value is where the baseline tick goes).
static func bars(c: Dictionary) -> Array:
	var out: Array = []
	for s: Array in STATS: out.append([s[0], norm(s, c), norm(s, {})])
	return out

## The plain-words line behind the bars (tooltip): "Speed 1.22x, Jump 1.12x, ...".
static func describe(c: Dictionary) -> String:
	var parts: PackedStringArray = []
	for s: Array in STATS:
		var v := float(c.get(s[1], 1.0))
		parts.append("%s %s" % [s[0], "x%.2f" % v if s[1] != "kb" else "x%.2f taken" % v])
	return ", ".join(parts)
