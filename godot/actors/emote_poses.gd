class_name EmotePoses
extends RefCounted
## The emote dances, ported 1:1 from the web game's `emotePose` (public/index.html ~4816). Visual only.
## pose(id, t, dur, yaw) says what every part of the body does at time t of the emote, for a fighter facing `yaw`:
##   yaw    extra body turn (spins), added to the rig yaw
##   lx, lz extra body lean (forward, sideways), added to the lean springs
##   hop    extra height of the whole rig; crouch 0..1 (squash, like squatting); pitch: whole-rig tilt back (wheelie)
##   aim    Vector3 world direction for the aiming arm (it springs there, stiff) or null
##   arm_l  Vector2 (rotation x, z) of the off arm or null; legs Vector2 (leg 0, leg 1 rotation x) or null
##   head   Vector2 kick for the head spring (scaled by dt * 20 by the caller) or null
## The props and particles of the big emotes (bike, lightning, stars, petals) are not ported yet.

static func _e(x: float) -> float:          # web `ease`: smoothstep on 0..1
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)

static func _cl(x: float) -> float:
	return clampf(x, 0.0, 1.0)

static func _d(fy: float, a: float, b: float, y: float) -> Vector3:   # a forward, b to the left, y up (world)
	return Vector3(sin(fy) * a + cos(fy) * b, y, cos(fy) * a - sin(fy) * b)

static func pose(id: String, t: float, dur: float, base_yaw: float) -> Dictionary:
	var u := _cl(t / dur)
	var P := {"yaw": 0.0, "lx": 0.0, "lz": 0.0, "hop": 0.0, "crouch": 0.0, "pitch": 0.0, "aim": null, "arm_l": null, "legs": null, "head": null}
	var tw := 0.0
	match id:
		"robot": tw = floorf(t * 2.2) * PI / 2.0
		"spin": tw = _e(u) * PI * 4.0
		"wobble": tw = u * PI * 3.0
		"devspin": tw = _e((u - 0.5) / 0.5) * PI * 4.0
		"galaxy": tw = _e(u) * PI * 6.0
		"pirouette": tw = _e((t - 0.55) / 2.35) * PI * 6.0
		"nova": tw = _e((t - 1.4) / 2.5) * PI * 4.0
		"sprinkler": tw = (floorf(t * 5.5) + _e(fmod(t * 5.5, 1.0) * 3.0)) * 0.42
	P["yaw"] = tw
	var fy := base_yaw + tw
	var env := minf(1.0, minf(t / 0.15, (dur - t) / 0.15))
	match id:
		"wobble":
			P["hop"] = absf(sin(t * 9.0)) * 0.3 * env; P["aim"] = _d(fy, 0.2, -0.9, 0.6 + 0.35 * sin(t * 10.0))
			P["arm_l"] = Vector2(0.0, 1.1 + 0.5 * sin(t * 10.0)); P["lz"] = sin(t * 9.0) * 0.25 * env
		"hip":
			P["lz"] = sin(t * 6.0) * 0.38 * env; P["crouch"] = 0.12 * env; P["aim"] = _d(fy, 0.55, sin(t * 6.0) * 0.9, -0.1)
			P["arm_l"] = Vector2(-0.5, 0.5 + 0.7 * cos(t * 6.0)); P["legs"] = Vector2(sin(t * 6.0) * 0.3, -sin(t * 6.0) * 0.3)
		"clap":
			var c := 0.5 + 0.5 * cos(t * 13.0)
			P["hop"] = absf(sin(t * 6.5)) * 0.12 * env; P["aim"] = _d(fy, 0.9, 0.12 + 0.55 * c, -0.2)
			P["arm_l"] = Vector2(-1.45, -0.55 + 0.7 * c); P["lx"] = 0.12 * sin(t * 6.5)
		"disco":
			var up := int(floorf(t * 2.8)) % 2 == 0
			P["hop"] = absf(sin(t * 5.6)) * 0.14 * env; P["lz"] = sin(t * 5.6) * 0.15
			P["aim"] = _d(fy, 0.35, -0.5, 0.95) if up else _d(fy, 0.2, 0.7, -0.8)
			P["arm_l"] = Vector2(-0.35, 1.0); P["legs"] = Vector2(sin(t * 5.6) * 0.35, -sin(t * 5.6) * 0.35)
		"sit":
			P["crouch"] = 0.95 * env; P["legs"] = Vector2(-1.25 * env, -1.25 * env); P["aim"] = _d(fy, 0.1, -0.7, 0.55 + 0.25 * sin(t * 9.0))
			P["arm_l"] = Vector2(0.0, 0.25); P["head"] = Vector2(0.0, sin(t * 3.0) * 1.2)
		"robot":
			var k := int(floorf(t * 4.0)) % 4
			P["aim"] = [_d(fy, 1, 0, 0.02), _d(fy, 0.1, -0.1, 1), _d(fy, 0.1, -1, 0.02), _d(fy, 0.4, 0, -0.9)][k]
			P["arm_l"] = [Vector2(-1.57, 0.1), Vector2(0, 0.2), Vector2(-1.57, 1.57), Vector2(0, 0.1)][(k + 2) % 4]
			var st := int(floorf(t * 4.0)) % 2 == 1
			P["legs"] = Vector2(0.55 if st else -0.15, -0.15 if st else 0.55)
		"spin":
			P["aim"] = _d(fy, 0, -1, 0.02); P["arm_l"] = Vector2(0.0, 1.55); P["crouch"] = 0.35 * sin(u * PI) * 0.6; P["lx"] = -0.18 * env
		"griddy":
			var sd := sin(t * 6.5)
			P["hop"] = absf(sd) * 0.1 * env; P["lz"] = sd * 0.22 * env; P["crouch"] = 0.3 * env; P["legs"] = Vector2(sd * 0.6, -sd * 0.6)
			P["aim"] = _d(fy, 0.25, -sd, -0.1 + 0.25 * absf(sd)); P["arm_l"] = Vector2(-0.3, 0.9 + 0.7 * sd); P["head"] = Vector2(0.0, sd)
		"floss":
			var sd := sin(t * 9.5)
			P["lz"] = -sd * 0.34 * env; P["crouch"] = 0.15 * env; P["legs"] = Vector2(sd * 0.25, -sd * 0.25)
			P["aim"] = _d(fy, 0.3, sd * 1.1, -0.35); P["arm_l"] = Vector2(-0.9, 0.7 - 0.8 * sd)
		"dab":
			var k := _e(t / 0.16) * _e((dur - t) / 0.22)
			P["lx"] = 0.2 * k; P["crouch"] = 0.1 * k; P["aim"] = _d(fy, 0.5 - 0.4 * k, -0.85 * k, 1.35 * k - 0.4)
			P["arm_l"] = Vector2(-1.45 * k, -1.05 * k); P["head"] = Vector2(1.5 * k, 0.0)
		"pump":
			var pu := absf(sin(t * 5.0))
			P["hop"] = pu * 0.18 * env; P["crouch"] = (1.0 - pu) * 0.25 * env; P["aim"] = _d(fy, 0.2, -0.1, 0.55 + 0.45 * pu); P["arm_l"] = Vector2(0.0, 0.3 + 0.9 * pu)
		"shimmy":
			var sh := sin(t * 15.0)
			P["lz"] = sh * 0.14 * env; P["lx"] = 0.12 * env; P["hop"] = absf(sin(t * 7.5)) * 0.06; P["aim"] = _d(fy, 0.35, -0.7, 0.15 * sh)
			P["arm_l"] = Vector2(-0.2, 0.7 + 0.2 * sh); P["head"] = Vector2(0.0, sh * 0.6)
		"jig":
			var hp := sin(t * 8.0)
			P["hop"] = absf(hp) * 0.34 * env; P["legs"] = Vector2(hp * 0.9, -hp * 0.9); P["aim"] = _d(fy, 0.1, 0.8 * hp, 0.6)
			P["arm_l"] = Vector2(0.0, 1.0 - 0.7 * hp); P["yaw"] = sin(t * 4.0) * 0.7
		"devspin":
			var ty := sin(t * 22.0)
			P["crouch"] = 0.2 * env; P["hop"] = absf(sin(t * 3.0)) * 0.1 * env; P["aim"] = _d(fy, 0.85, -0.15 + 0.1 * ty, -0.1 + 0.08 * ty)
			P["arm_l"] = Vector2(-1.35, 0.35 - 0.1 * ty); P["head"] = Vector2(0.4 * env, 0.0)
		"betahop":
			var hp := sin(t * 7.0)
			P["hop"] = absf(hp) * 0.4 * env; P["legs"] = Vector2(hp * 0.8, -hp * 0.8); P["aim"] = _d(fy, 0.2, -0.3, 0.9)
			P["arm_l"] = Vector2(0.0, 1.0 + 0.3 * hp); P["yaw"] = sin(t * 3.5) * 0.5
		"crane":
			var k := minf(_e(t / 0.35), _e((dur - t) / 0.4))
			var L1 := _pulse(t, 0.35, 0.7, 1.0, 1.25)
			var L2 := _pulse(t, 1.3, 1.65, 1.85, 2.1)
			var kick := _pulse(t, 1.6, 1.74, 1.9, 2.25)
			P["crouch"] = 0.12 * k + 0.1 * kick; P["hop"] = (0.05 * absf(sin(t * 4.0)) * k) * (1.0 - kick) + 0.3 * kick
			P["lx"] = (-0.1 * (L1 + L2) - 0.28 * kick) * k; P["legs"] = Vector2(-1.25 * L1 * k, -(0.7 * L2 + 0.85 * kick) * k)
			P["aim"] = _d(fy, 0.1 + 0.9 * kick, -0.95 * (1.0 - kick), 0.85 - 0.5 * kick); P["arm_l"] = Vector2(-1.4 * kick, 2.3 * (1.0 - kick) + 0.15 * kick)
			P["head"] = Vector2(-0.2 * k, 0.0)
		"land":
			var fall := _cl(t / 0.4)
			var g1 := _e((t - 0.4) / 0.1) * _e((dur - t) / 0.5)
			P["hop"] = 1.4 * (1.0 - fall * fall) if t < 0.4 else 0.0; P["crouch"] = 0.95 * g1
			P["lx"] = -0.15 * (1.0 - fall) if t < 0.4 else 0.3 * g1; P["legs"] = Vector2(-1.25 * g1, 0.25 * g1)
			P["lz"] = sin((t - 0.4) * 55.0) * 0.1 if t > 0.4 and t < 0.62 else 0.0
			P["aim"] = _d(fy, lerpf(0.2, 0.3, g1), lerpf(-0.9, -0.55, g1), lerpf(0.9, -1.0, g1))
			P["arm_l"] = Vector2(lerpf(0.0, 0.9, g1), lerpf(2.2, 0.8, g1)); P["head"] = Vector2(0.9 * g1, 0.0)
		"guitar":
			var wind := t > dur - 0.95
			var a := t * 20.0
			var w0 := t - (dur - 0.95)
			P["lx"] = -0.3 * env; P["crouch"] = 0.22 * env; P["legs"] = Vector2(-0.25 * env, 0.3 * env)
			P["hop"] = absf(sin(w0 * 3.3)) * 0.5 * env if wind else 0.04 * env * absf(sin(t * 7.0))
			P["aim"] = _d(fy, 0.15, sin(a) * 0.95, cos(a) * 0.95) if wind else _d(fy, 0.55, 0.35, -0.3 + 0.4 * sin(t * 15.0))
			P["arm_l"] = Vector2(-1.35, -0.3); P["head"] = Vector2(sin(t * 7.0) * 1.6 * env, sin(t * 3.5) * 0.6)
		"galaxy":
			var hh := minf(_e(t / 1.3), _e((dur - t) / 1.1))
			P["hop"] = 1.6 * hh + 0.1 * sin(t * 3.0) * hh; P["lx"] = -0.18 * hh; P["aim"] = _d(fy, 0.0, -1.0, 0.1 + 0.15 * sin(t * 2.0))
			P["arm_l"] = Vector2(0.0, 1.5 + 0.1 * sin(t * 2.0)); P["legs"] = Vector2(0.15 * hh * sin(t * 2.0), -0.15 * hh * sin(t * 2.0)); P["head"] = Vector2(-0.4 * hh, 0.0)
		"pirouette":
			var rise := _e((t - 0.35) / 0.35) * _e((3.0 - t) / 0.3)
			var spin := _e((t - 0.55) / 0.2) * _e((2.95 - t) / 0.2)
			var cur := _e((t - 3.1) / 0.35) * _e((dur - 0.1 - t) / 0.3)
			var pre := _e(t / 0.3) * _e((0.5 - t) / 0.2)
			P["crouch"] = 0.28 * pre + 0.12 * cur; P["hop"] = 0.26 * rise + 0.05 * spin * absf(sin(t * 9.0)); P["lx"] = 0.22 * cur - 0.06 * spin
			P["legs"] = Vector2(-0.75 * spin, 0.05 * rise)
			P["aim"] = _d(fy, 0.15 * (1.0 - rise) + 0.1 * cur, -0.45 * (1.0 - rise) - 0.5 * cur, 1.0 * rise - 0.75 * (1.0 - rise) - 0.5 * cur)
			P["arm_l"] = Vector2(0.0, (0.5 + 2.3 * rise) * (1.0 - cur) + 0.5 * cur); P["head"] = Vector2(0.18 * cur - 0.1 * rise, 0.0)
		"storm":
			var charge := _e(t / 0.6) * (1.0 - _e((t - 0.95) / 0.08))
			var up := _e((t - 1.0) / 0.16) * _e((2.7 - t) / 0.2)
			var slam := _e((t - 2.68) / 0.12) * _e((dur - 0.05 - t) / 0.7)
			P["crouch"] = 0.55 * charge + 0.95 * slam; P["hop"] = 0.6 * up + 0.08 * up * sin(t * 9.0); P["lz"] = sin(t * 60.0) * 0.045 * charge
			P["lx"] = -0.12 * up + 0.3 * slam; P["legs"] = Vector2(-0.35 * charge - 0.5 * slam, -0.35 * charge - 0.5 * slam)
			var a0 := Vector3(0.1, -0.5, -0.7)
			var a1 := Vector3(0.05, -0.15, 1.0)
			var a2 := Vector3(0.4, -0.3, -1.0)
			var m := a0 + (a1 - a0) * up + (a2 - a0) * slam
			P["aim"] = _d(fy, m.x, m.y, m.z)
			P["arm_l"] = Vector2(0.2 * slam, 0.45 + 2.4 * up + 0.2 * slam); P["head"] = Vector2(-0.5 * up + 0.35 * slam, sin(t * 50.0) * 0.08 * charge)
		"nova":
			var coil := _e(t / 0.6) * _e((1.28 - t) / 0.1)
			var rise := _e((t - 1.25) / 0.3) * _e((4.0 - t) / 0.8)
			var land := _e((t - 4.35) / 0.15) * _e((dur - 0.05 - t) / 0.45)
			P["crouch"] = 0.65 * coil + 0.55 * land; P["hop"] = 1.6 * rise + 0.12 * rise * sin(t * 3.0); P["lz"] = sin(t * 45.0) * 0.04 * coil
			P["lx"] = 0.25 * coil - 0.15 * rise + 0.2 * land
			P["legs"] = Vector2(-0.6 * coil + 0.18 * rise * sin(t * 2.0) - 0.4 * land, -0.6 * coil - 0.18 * rise * sin(t * 2.0) - 0.4 * land)
			P["aim"] = _d(fy, 0.4 * coil * (1.0 - rise) + 0.15 * rise, -0.5 * coil - 1.0 * rise * (1.0 - coil) - 0.3 * land, -0.55 * coil + 0.5 * rise * (1.0 - coil) - 0.5 * land)
			P["arm_l"] = Vector2(-0.8 * coil, 0.5 * coil + 2.1 * rise * (1.0 - coil) + 0.3 * land); P["head"] = Vector2(0.4 * coil - 0.45 * rise, 0.0)
		"wheelie":
			var rev := _e((t - 0.25) / 0.35)
			var up := _e((t - 1.15) / 0.5)
			var dn := _e((t - 3.55) / 0.5)
			var pit := up * (1.0 - dn)
			var dip := sin(_cl((t - 0.8) / 0.35) * PI) * 0.12
			var bump := absf(sin((t - 4.05) * 11.0)) * 0.07 * (1.0 - (t - 4.05) / 0.35) if t > 4.05 and t < 4.4 else 0.0
			P["pitch"] = 0.72 * pit - dip + 0.012 * sin(t * 45.0) * rev * (1.0 - pit) + 0.035 * sin(t * 3.4) * pit
			P["hop"] = 0.15 * _e(t / 0.2) * _e((dur - t) / 0.25) + bump
			P["lx"] = 0.1 * rev * (1.0 - pit) - 0.08 * pit; P["legs"] = Vector2(-0.38 + 0.08 * pit, -0.38 + 0.08 * pit)
			P["aim"] = _d(fy, 0.62, -0.2, -0.8 + 0.3 * pit); P["arm_l"] = Vector2(-1.0 + 0.1 * pit, 0.12); P["head"] = Vector2(-0.25 * pit, 0.0)
		"flex":
			var pu := 0.5 + 0.5 * sin(t * 7.0)
			P["hop"] = 0.05 * pu * env; P["crouch"] = 0.12 * pu * env; P["aim"] = _d(fy, 0.1, -0.7, 0.9 + 0.3 * pu)
			P["arm_l"] = Vector2(0.0, 2.35 + 0.25 * pu); P["head"] = Vector2(0.0, sin(t * 3.5) * 0.35 * env)
		"salute":
			var k := _e(t / 0.3) * _e((1.9 - t) / 0.25)
			var hp := _cl((t - 1.9) / 0.5)
			P["aim"] = _d(fy, 0.5 * k, -0.35 * k, 1.1 * k - 1.0 * (1.0 - k)); P["arm_l"] = Vector2(0.0, 0.12); P["hop"] = sin(hp * PI) * 0.45
			P["head"] = Vector2(-0.15 * k, 0.0); P["legs"] = Vector2.ZERO
		"bow":
			var k := _e(t / 0.55) * _e((dur - 0.35 - t) / 0.55)
			P["lx"] = 1.0 * k; P["aim"] = _d(fy, 0.55, -0.1, -0.6 + 0.1 * k); P["arm_l"] = Vector2(-0.7 * k, 0.1); P["head"] = Vector2(0.3 * k, 0.0); P["legs"] = Vector2.ZERO
		"zombie":
			var st := sin(t * 6.0)
			P["hop"] = absf(st) * 0.08 * env; P["lx"] = 0.16 * env; P["lz"] = 0.1 * st * env; P["aim"] = _d(fy, 1.0, -0.1, 0.05 + 0.05 * st)
			P["arm_l"] = Vector2(-1.5 + 0.1 * st, 0.08); P["legs"] = Vector2(0.4 * st, -0.4 * st); P["head"] = Vector2(0.3 * env, sin(t * 2.2) * 0.8 * env)
		"sprinkler":
			P["hop"] = absf(sin(t * 11.0)) * 0.04 * env; P["crouch"] = 0.06 * env
			P["aim"] = _d(fy, 0.95, -0.15 - 0.05 * sin(t * 22.0), 0.12 + 0.06 * sin(t * 22.0)); P["arm_l"] = Vector2(-2.1, 0.55); P["head"] = Vector2(0.0, 0.2 * sin(t * 11.0))
		"cartwheel":
			var j := _cl((t - 0.15) / 1.1)
			P["hop"] = sin(j * PI) * 1.0; P["lz"] = -_e(j) * PI * 2.0; P["legs"] = Vector2(0.55 * sin(j * PI), -0.55 * sin(j * PI))
			P["aim"] = _d(fy, 0, -0.5, 1); P["arm_l"] = Vector2(0.0, 2.7 * sin(j * PI) + 0.2)
			P["crouch"] = 0.4 * (t / 0.15) if t < 0.15 else 0.4 * _cl(1.0 - (t - 0.15) / 0.12) * (0.0 if j >= 1.0 else 1.0)
		"flip":
			var j := _cl((t - 0.12) / 1.0)
			P["hop"] = sin(j * PI) * 1.5; P["lx"] = -_e(j) * PI * 2.0; P["legs"] = Vector2(-1.2 * sin(j * PI), -1.2 * sin(j * PI))
			P["aim"] = _d(fy, 0.1, -0.2, 1); P["arm_l"] = Vector2(PI, 0.2)
			P["crouch"] = 0.7 * (t / 0.12) if t < 0.12 else 0.7 * _cl(1.0 - (t - 0.12) / 0.15) * (0.0 if j >= 1.0 else 1.0)
	return P

static func _pulse(t: float, a: float, b: float, c: float, d: float) -> float:
	return _e((t - a) / (b - a)) * _e((d - t) / (d - c))
