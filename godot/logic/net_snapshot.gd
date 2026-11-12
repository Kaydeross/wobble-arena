class_name NetSnapshot
extends RefCounted
## Encode/decode of the in-match messages in docs/PROTOCOL.md section 3.1: the 30 Hz `S` state entry, the hit `h`
## and the K.O. `ko`. Matches the web game byte for byte where it matters: numbers are rounded exactly like
## JavaScript's `+v.toFixed(n)` and `Math.round`, and incoming hits are cleaned like `netCleanHit` / `netGuard`.

const HIT_MAX_D := 250.0
const HIT_MAX_F := 120.0
const NET_MAX := 8

# ============================== `S` (state) ==============================

## One `S` entry for a fighter this client runs. `extra` may hold `lv`, `el`, `pt` (Pillars clock, host only), `sq`.
static func encode_entry(f: FighterState, extra: Dictionary = {}) -> Dictionary:
	var p := f.phys
	var e := {"id": f.net_slot, "x": fixed(p.px, 2), "y": fixed(p.py, 2), "z": fixed(p.pz, 2),
		"vx": fixed(p.vx, 2), "vy": fixed(p.vy, 2), "vz": fixed(p.vz, 2), "yaw": fixed(f.yaw, 2),
		"ax": fixed(f.arm_x, 2), "ay": fixed(f.arm_y, 2), "az": fixed(f.arm_z, 2),
		"w": null if f.dead else f.weapon, "hp": Combat.js_round(f.hp), "d": 1 if f.dead else 0,
		"g": 1 if p.grounded else 0, "sq": int(extra.get("sq", 0)), "iv": 1 if f.invuln > 0.0 else 0,
		"lv": f.lives, "el": 1 if f.elim else 0}
	if extra.has("pt"): e["pt"] = Combat.js_round(float(extra["pt"]))
	return e

static func encode_state(entries: Array) -> Dictionary:
	return {"t": "S", "l": entries}

## A received `S` -> its valid entries (each checked by decode_entry). `guard_slot` >= 0: the host checking a guest,
## who may only speak for its own fighter (netGuard: first object entry only, id forced to the slot).
static func decode_state(m: Variant, guard_slot: int = -1) -> Array:
	var out := []
	if not (m is Dictionary) or m.get("t") != "S" or not (m.get("l") is Array):
		return out
	for it: Variant in m["l"]:
		if not (it is Dictionary): continue
		if guard_slot >= 0:
			var c: Dictionary = it.duplicate()
			c["id"] = guard_slot
			var one := decode_entry(c)
			if not one.is_empty(): out.append(one)
			return out
		var d := decode_entry(it)
		if not d.is_empty(): out.append(d)
	return out

## One entry -> typed values, or {} when it is unusable (missing/non-finite position, bad slot).
static func decode_entry(it: Variant) -> Dictionary:
	if not (it is Dictionary):
		return {}
	var id := to_int32(it.get("id"))
	if id < 0 or id >= NET_MAX or not _finite(it.get("id")):
		return {}
	var r := {"id": id}
	for k in ["x", "y", "z"]:
		if not _finite(it.get(k)): return {}
		r[k] = float(it[k])
	for k in ["vx", "vy", "vz", "yaw", "ax", "ay", "az", "hp"]:
		r[k] = num(it.get(k), -1e6, 1e6, 0.0)
	var w: Variant = it.get("w")
	r["w"] = w if w is String and w.length() <= 24 else ""
	for k in ["d", "g", "sq", "iv", "el"]:
		r[k] = to_int32(it.get(k)) == 1
	r["lv"] = to_int32(it.get("lv"))
	if it.has("pt"): r["pt"] = num(it["pt"], -1e6, 1e6, 0.0)
	return r

# ============================== `h` (hit) and `ko` ==============================

## Fighter.hit on a ghost: `to` = the slot that applies it (the victim if human, 0 for a bot), `vs` = victim slot.
static func encode_hit(to: int, vs: int, from: int, d: float, x: float, y: float, z: float, f: float, head: bool) -> Dictionary:
	return {"t": "h", "to": to, "vs": vs, "from": from, "d": fixed(d, 2), "x": fixed(x, 3), "y": fixed(y, 3), "z": fixed(z, 3),
		"f": fixed(f, 2), "hd": 1 if head else 0}

## A received `h`, cleaned (netCleanHit: d 0..250, f 0..120, direction -2..2, junk -> 0). {} = drop it.
## `guard_slot` >= 0: the host checking a guest's message (the guest may only claim hits it made itself).
static func decode_hit(m: Variant, guard_slot: int = -1) -> Dictionary:
	if not (m is Dictionary) or m.get("t") != "h":
		return {}
	if guard_slot >= 0 and to_int32(m.get("from")) != guard_slot:
		return {}
	var vs := to_int32(m.get("vs"))
	if vs < 0 or vs >= NET_MAX:
		return {}
	return {"t": "h", "to": to_int32(m.get("to")), "vs": vs, "from": guard_slot if guard_slot >= 0 else to_int32(m.get("from")),
		"d": num(m.get("d"), 0.0, HIT_MAX_D, 0.0), "f": num(m.get("f"), 0.0, HIT_MAX_F, 0.0),
		"x": num(m.get("x"), -2.0, 2.0, 0.0), "y": num(m.get("y"), -2.0, 2.0, 0.0), "z": num(m.get("z"), -2.0, 2.0, 0.0),
		"hd": to_int32(m.get("hd")) != 0}

static func encode_ko(from: int, to: int) -> Dictionary:
	return {"t": "ko", "from": from, "to": to}

## A received `ko`; with `guard_slot` the guest may only report its own death.
static func decode_ko(m: Variant, guard_slot: int = -1) -> Dictionary:
	if not (m is Dictionary) or m.get("t") != "ko":
		return {}
	var to := to_int32(m.get("to"))
	if guard_slot >= 0 and to != guard_slot:
		return {}
	if to < 0 or to >= NET_MAX:
		return {}
	var from := to_int32(m.get("from"))
	return {"t": "ko", "from": from if from >= 0 and from < NET_MAX else -1, "to": to}

# ============================== JavaScript number semantics ==============================

## netNum: `+v`, finite -> clamped to lo..hi, anything else -> def.
static func num(v: Variant, lo: float, hi: float, def: float) -> float:
	var x := _js_number(v)
	if is_nan(x) or is_inf(x):
		return def
	return maxf(lo, minf(hi, x))

## `v | 0` (ToInt32) for the values JSON can carry.
static func to_int32(v: Variant) -> int:
	var x := _js_number(v)
	if is_nan(x) or is_inf(x):
		return 0
	var t := int(x) if absf(x) < 9.2e18 else 0
	t = t & 0xFFFFFFFF
	return t - 0x100000000 if t >= 0x80000000 else t

static func _finite(v: Variant) -> bool:
	return (v is float or v is int) and not is_nan(float(v)) and not is_inf(float(v))

## Unary `+` on a JSON value (arrays/objects -> NaN; good enough for validation).
static func _js_number(v: Variant) -> float:
	if v == null: return 0.0
	if v is bool: return 1.0 if v else 0.0
	if v is int or v is float: return float(v)
	if v is String:
		var s: String = v.strip_edges()
		if s == "": return 0.0
		return s.to_float() if s.is_valid_float() else NAN
	return NAN

## Exactly `+v.toFixed(digits)`: the nearest multiple of 10^-digits to the real value of v, ties away from zero.
## (v * 10^digits is computed exactly as a double-double so cases like 1.005 round like JavaScript, to 1.)
static func fixed(v: float, digits: int) -> float:
	if is_nan(v) or is_inf(v):
		return v
	if v < 0.0:
		var neg := -fixed(-v, digits)
		return 0.0 if neg == 0.0 else neg
	var scale := pow(10.0, digits)
	var p := v * scale
	var e := _two_product_err(v, scale, p)
	var n := floorf(p)
	var g := (p - n) - 0.5
	if g + e >= 0.0:
		n += 1.0
	return n / scale

static func _two_product_err(a: float, b: float, p: float) -> float:
	var ca := 134217729.0 * a
	var ah := ca - (ca - a)
	var al := a - ah
	var cb := 134217729.0 * b
	var bh := cb - (cb - b)
	var bl := b - bh
	return ((ah * bh - p) + ah * bl + al * bh) + al * bl
