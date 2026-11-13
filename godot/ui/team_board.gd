class_name TeamBoard
extends Control
## Team scoreboard for team modes (top centre): one chip per team with a colour block, the team name and its score; your
## own team's chip is lit and tagged "You". Replaces the old "Team 0 v 0 / 50" text line. Fed by world.gd every frame.

const CHIP := Vector2(158, 42)
const GAP := 96.0
const NAMES := ["Blue", "Red"]

var scores := [0, 0]
var mine := 0
var limit := 0
var _font: Font

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = UiTheme.font(700)
	custom_minimum_size = Vector2(CHIP.x * 2.0 + GAP, CHIP.y + 18.0)
	size = custom_minimum_size

func set_data(s0: int, s1: int, my_team: int, lim: int) -> void:
	if scores[0] == s0 and scores[1] == s1 and mine == my_team and limit == lim: return
	scores = [s0, s1]; mine = my_team; limit = lim
	queue_redraw()

func _team_color(i: int) -> Color:
	return Color.hex((int(ModeRules.TEAM_COL[i]) << 8) | 0xff)

func _draw() -> void:
	if _font == null: _font = UiTheme.font(700)
	for i in 2:
		var x := i * (CHIP.x + GAP)
		var r := Rect2(Vector2(x, 14), CHIP)
		var col := _team_color(i)
		var lit := i == mine
		var bg := Color(UiTheme.PANEL.r, UiTheme.PANEL.g, UiTheme.PANEL.b, 0.9)
		var sb := UiTheme.box(bg, 14, col if lit else Color(col.r, col.g, col.b, 0.45), 4 if lit else 2, 4)
		if lit:
			sb.shadow_color = Color(col.r, col.g, col.b, 0.5); sb.shadow_size = 10; sb.shadow_offset = Vector2.ZERO
		draw_style_box(sb, r)
		# the colour block
		draw_style_box(UiTheme.box(col, 9, Color(1, 1, 1, 0.9), 2, 0), Rect2(r.position + Vector2(8, 8), Vector2(26, 26)))
		draw_string(_font, r.position + Vector2(42, 27), NAMES[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, 0.8))
		var s := str(scores[i])
		var sw := _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
		var sp := Vector2(r.end.x - 12.0 - sw, r.position.y + 31.0)
		draw_string_outline(_font, sp, s, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, 5, Color(0, 0, 0, 0.45))
		draw_string(_font, sp, s, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color.WHITE)
		if lit:                                                    # "YOU" tag riding the top edge
			var pill := Rect2(Vector2(r.position.x + CHIP.x / 2.0 - 22.0, 0), Vector2(44, 18))
			draw_style_box(UiTheme.box(col, 9, Color(1, 1, 1, 0.9), 2, 0), pill)
			var yw := _font.get_string_size("You", HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			draw_string(_font, pill.position + Vector2((pill.size.x - yw) / 2.0, 13.5), "You", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
	var mid := "First to %d" % limit if limit > 0 else "vs"
	var mw := _font.get_string_size(mid, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	draw_string(_font, Vector2(CHIP.x + (GAP - mw) / 2.0, 40), mid, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiTheme.MUTED)
