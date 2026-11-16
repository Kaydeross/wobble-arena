extends RefCounted
## The lowest graphics tier (and any pack without its own style): one plain colour panel in the pack's colour wipes in from
## the left, shows the pack's name, and wipes out to the right. No particles, no shader.

var cues := [[0.3, "pop", 0.6]]

func setup(_t: PackTransition) -> void:
	pass

func tick(_t: PackTransition) -> void:
	pass

func draw(t: PackTransition) -> void:
	var w := t.size.x
	var h := t.size.y
	var lead := PackTransition.smooth(t.cover()) * w
	var trail := PackTransition.smooth(t.reveal()) * w
	var r := Rect2(trail, 0.0, maxf(0.0, lead - trail), h)
	if r.size.x < 1.0: return
	t.draw_rect(r, t.accent.darkened(0.55))
	t.draw_rect(Rect2(r.position.x, 0.0, r.size.x, h * 0.06), t.accent)
	t.draw_rect(Rect2(r.position.x, h * 0.94, r.size.x, h * 0.06), t.accent)
	var a := PackTransition.env(t.p, 0.2, 0.45, 0.55, 0.8)
	t.banner(t.label, t.size * 0.5, w * 0.8, Color.WHITE, t.accent.darkened(0.6), a, 1.0, 54)
