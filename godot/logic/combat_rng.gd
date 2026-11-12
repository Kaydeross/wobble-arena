class_name CombatRng
extends RefCounted
## The random source for combat logic (stands in for Math.random in the web game).
## Park-Miller "minimal standard" generator: state = state * 48271 mod (2^31 - 1).
## Every intermediate value stays below 2^47, so JavaScript doubles compute exactly the same stream;
## tools/combat-reference.js installs the same generator as Math.random, which is what makes the parity test possible.
## In a real match seed it from anything (the default picks a random seed).

const MOD := 2147483647
var state := 1

func _init(seed_value: int = 0) -> void:
	if seed_value <= 0:
		seed_value = randi() % (MOD - 1) + 1
	state = seed_value % MOD
	if state == 0:
		state = 1

## Like Math.random(): [0, 1).
func next() -> float:
	state = (state * 48271) % MOD
	return float(state - 1) / 2147483646.0

## Like rand(a, b) in the web game: a + Math.random() * (b - a).
func range_f(a: float, b: float) -> float:
	return a + next() * (b - a)
