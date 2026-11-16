class_name FitText
extends RefCounted
## Picks the largest font size (at most `max_size`, at least `min_size`) at which a TRANSLATED string fits the room it
## has, with the real UI font and the CJK fallback of the language in use (Lang.apply). One answer for every language:
## English keeps its designed size (it fits), a longer word (fr / es) or a wider script (zh / ja) steps down just enough.
## Call it again after a language change or a resize (scripts/main.gd apply_safe_area does for the title).

const MIN_SIZE := 12        ## canvas px, never smaller (about 9 pt on a phone; UiTheme.MIN_FONT is the design floor, the fit may dip 2 below it)

## Width of the widest line of `text` at `fs`.
static func line_width(font: Font, text: String, fs: int) -> float:
	var w := 0.0
	for l in text.split("\n"): w = maxf(w, font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	return w

## The largest size in [min_size, max_size] whose widest line is <= avail_w (and, when avail_h > 0, whose lines are <= avail_h tall).
static func size_for(font: Font, text: String, max_size: int, avail_w: float, min_size := MIN_SIZE, avail_h := 0.0) -> int:
	var lines := text.count("\n") + 1
	var fs := maxi(max_size, min_size)
	while fs > min_size:
		if line_width(font, text, fs) <= avail_w and (avail_h <= 0.0 or font.get_height(fs) * lines <= avail_h): break
		fs -= 1
	return fs

## Sets `l`'s font size to fit `avail_w`; returns it.
static func label(l: Label, max_size: int, avail_w: float, min_size := MIN_SIZE) -> int:
	var fs := size_for(l.get_theme_font("font"), l.tr(l.text), max_size, avail_w, min_size)
	l.add_theme_font_size_override("font_size", fs)
	return fs

## Sets `b`'s font size so its text fits `avail_w` (the room for the text itself: the caller subtracts the button's padding).
static func button(b: Button, max_size: int, avail_w: float, min_size := MIN_SIZE) -> int:
	var fs := size_for(b.get_theme_font("font"), b.tr(b.text), max_size, avail_w, min_size)
	b.add_theme_font_size_override("font_size", fs)
	return fs

## Like label(), but a line that still does not fit at `min_size` wraps onto at most `lines` lines instead of being trimmed with "...".
static func label_or_wrap(l: Label, max_size: int, avail_w: float, min_size := MIN_SIZE, lines := 2) -> int:
	var fs := label(l, max_size, avail_w, min_size)
	var fits := line_width(l.get_theme_font("font"), l.tr(l.text), fs) <= avail_w
	l.autowrap_mode = TextServer.AUTOWRAP_OFF if fits else TextServer.AUTOWRAP_WORD_SMART
	l.max_lines_visible = -1 if fits else lines
	l.clip_text = fits
	return fs
