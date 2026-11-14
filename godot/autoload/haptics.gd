extends Node
## Haptic feedback (autoload `Haptics`): short device vibrations for the moments that should be felt as well as seen.
## iOS and Android both expose vibration through Input.vibrate_handheld(); desktop and web have no motor, so every call
## is a no-op there. Settings > Audio > "Haptics (vibration)" turns it off.
##
## Platform difference, on purpose: Android honours the requested length, so hit / hurt / heavy get 25 / 55 / 120 ms and
## each weight is rate-limited so a stream of hits cannot become one long buzz. iOS only plays the fixed system vibrate
## (~0.4 s) whatever length is asked for, so only the heavy moments (a K.O., an explosion) are played there, at least a
## second apart; light and medium weights are skipped rather than turning every hit into a full buzz.

const LIGHT := 0      ## a hit that lands
const MEDIUM := 1     ## being hit, a heavy weapon, a big landing
const HEAVY := 2      ## a K.O. or an explosion

const MS := [25, 55, 120]          ## Android vibration length per weight
const GAP_MS := [55, 110, 700]     ## minimum time between two vibrations of that weight (the heavy one is longer on a phone that only does the system buzz)

var _last := [-1, -1, -1]
var _ios := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ios = OS.has_feature("ios")

func supported() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("ios") or OS.has_feature("android")

func on() -> bool:
	return bool(Settings.get_value("haptics", true))

## Play a vibration of `weight` (LIGHT / MEDIUM / HEAVY). Silent when turned off or on a device without a motor.
func buzz(weight: int = LIGHT) -> void:
	if not on() or not supported(): return
	var w := clampi(weight, LIGHT, HEAVY)
	if _ios and w < HEAVY: return
	var now := Time.get_ticks_msec()
	if _last[w] >= 0 and now - _last[w] < GAP_MS[w]: return
	_last[w] = now
	Input.vibrate_handheld(MS[w])

## Ready-made weights for the call sites.
func hit() -> void: buzz(LIGHT)
func hurt() -> void: buzz(MEDIUM)
func heavy() -> void: buzz(HEAVY)

## Test hook: forget the rate limits so a test can observe two calls in a row.
func reset() -> void:
	_last = [-1, -1, -1]
