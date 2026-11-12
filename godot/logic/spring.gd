class_name Spring2
extends RefCounted
## 2D damped spring used for all floppy limb / head wobble. Exact port of the web `class Spring2`
## (public/index.html, CODEMAP section 5); parity-tested by tools/test-spring.js. Plain 64-bit floats.

var x: float = 0.0
var y: float = 0.0
var vx: float = 0.0
var vy: float = 0.0


## One semi-implicit Euler step: stiffness k, damping ratio zeta, external force (fx, fy), rest target (tx, ty).
func step(dt: float, k: float, zeta: float, fx: float, fy: float, tx: float = 0.0, ty: float = 0.0) -> void:
	var c: float = 2.0 * sqrt(k) * zeta
	vx += (-k * (x - tx) - c * vx + fx) * dt
	vy += (-k * (y - ty) - c * vy + fy) * dt
	x += vx * dt
	y += vy * dt


## Instant velocity impulse.
func kick(ix: float, iy: float) -> void:
	vx += ix
	vy += iy


func reset() -> void:
	x = 0.0
	y = 0.0
	vx = 0.0
	vy = 0.0
