@tool
extends Node2D
## A speech balloon in the game's pixel style that grows to fit what it
## says. Text wraps to MAX_WIDTH and runs over pages of up to MAX_LINES; a
## blank line in the text also starts a new page. Each page pops open from
## the tail, types itself out and waits to be read; advance() finishes the
## typing, then turns the page, then closes the balloon. Pages left alone
## turn by themselves once they've had time to be read.
## Sizes are in game pixels, with the tail pointing up at anchor. Text is
## drawn at twice the game resolution, like the now playing info.
## Runs in the editor too, for the Moon Tips preview (addons/moon_tips).

signal closed

enum State { HIDDEN, OPENING, TYPING, READING, CLOSING }

const FONT := preload("res://fonts/Silkscreen-Regular.ttf")
const LINE_HEIGHT := 4
## From the balloon's top edge to the top of the first line's caps, and
## from the last line's caps to the bottom edge.
const PAD_TOP := 2.0
const PAD_BOTTOM := 2.0
## From the balloon's side edges to the text.
const PAD_SIDE := 3
## Widest the balloon gets, and how close it comes to the screen's sides.
const SCREEN_WIDTH := 72
const MARGIN := 2
const MAX_WIDTH := SCREEN_WIDTH - 2 * MARGIN
## Three lines keep the balloon clear of the sound tower under the moon.
const MAX_LINES := 3
## Silkscreen leaves this much room above its caps, which are this tall,
## in game pixels.
const CAP_TOP := 1.5
const CAP_HEIGHT := 2.5
## Rows between the tail's tip and the balloon's top edge; the tail
## widens by a pixel each side per row.
const TAIL := 3
const FILL := Color(0.9, 0.9, 0.9)
const TEXT_COLOR := Color(0.12, 0.12, 0.12)
## Seconds to pop open or shut.
const OPEN_TIME := 0.12
const CHARS_PER_SECOND := 30.0
## Seconds a typed page stays up before turning by itself, plus a bit
## per character so long pages get longer.
const READ_TIME := 2.0
const READ_TIME_PER_CHAR := 0.06

## One game pixel in screen pixels. Text is drawn at 4 * px, so px should
## be even for crisp half-pixel text.
var px := 10
## Where the tail's tip points, in game pixels.
var anchor := Vector2i(SCREEN_WIDTH / 2, 0)

var _state := State.HIDDEN
var _pages: Array[PackedStringArray] = []
var _page := 0
## The current page's balloon, without its tail.
var _rect := Rect2i()
var _tail_x := 0
## How far open (0 to 1) while opening or closing.
var _open := 0.0
var _shown := 0.0
var _page_chars := 0
var _read_timer := 0.0


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


## Opens the balloon saying text, replacing whatever it was saying.
func say(text: String) -> void:
	_pages = paginate(text, px)
	if _pages.is_empty():
		return
	_page = 0
	_layout()
	_state = State.OPENING
	_open = 0.0
	queue_redraw()


## Finishes typing the page, else turns it, else closes the balloon.
func advance() -> void:
	match _state:
		State.OPENING:
			_open = 1.0
			_start_typing()
		State.TYPING:
			_shown = _page_chars
			_finish_page()
		State.READING:
			if _page + 1 < _pages.size():
				_page += 1
				_layout()
				_start_typing()
			else:
				_state = State.CLOSING
	queue_redraw()


## Shuts the balloon, whatever it was saying.
func close() -> void:
	if _state != State.HIDDEN:
		_state = State.CLOSING
		queue_redraw()


func is_talking() -> bool:
	return _state != State.HIDDEN


func is_typing() -> bool:
	return _state == State.TYPING


## True when point (game pixels) is on the open balloon or its tail.
func has_point(point: Vector2) -> bool:
	if _state == State.HIDDEN:
		return false
	var tail := Rect2i(_tail_x - TAIL + 1, anchor.y, 2 * TAIL - 1, TAIL)
	return Rect2(_rect.merge(tail)).has_point(point)


## Splits text into the pages the balloon shows, each a few upper case
## lines that fit its widest. Blank lines start new pages.
static func paginate(text: String, pixel := 10) -> Array[PackedStringArray]:
	var pages: Array[PackedStringArray] = []
	var page := PackedStringArray()
	var width := (MAX_WIDTH - 2 * PAD_SIDE) * pixel
	for paragraph in text.to_upper().split("\n"):
		paragraph = paragraph.strip_edges()
		if paragraph == "":
			if not page.is_empty():
				pages.append(page)
				page = PackedStringArray()
			continue
		for line in _wrap(paragraph, width, 4 * pixel):
			if page.size() == MAX_LINES:
				pages.append(page)
				page = PackedStringArray()
			page.append(line)
	if not page.is_empty():
		pages.append(page)
	return pages


## Breaks a paragraph into lines no wider than width, between words where
## it can and inside words too long for a line.
static func _wrap(paragraph: String, width: float, font_size: int) -> PackedStringArray:
	var lines := PackedStringArray()
	var line := ""
	for word in paragraph.split(" ", false):
		var joined := word if line == "" else line + " " + word
		if _width(joined, font_size) <= width:
			line = joined
			continue
		if line != "":
			lines.append(line)
		line = word
		while _width(line, font_size) > width:
			var fit := line.length() - 1
			while fit > 1 and _width(line.left(fit), font_size) > width:
				fit -= 1
			lines.append(line.left(fit))
			line = line.substr(fit)
	if line != "":
		lines.append(line)
	return lines


static func _width(text: String, font_size: int) -> float:
	return FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x


func _process(delta: float) -> void:
	match _state:
		State.OPENING:
			_open = minf(_open + delta / OPEN_TIME, 1.0)
			if _open >= 1.0:
				_start_typing()
			queue_redraw()
		State.TYPING:
			var before := int(_shown)
			_shown = minf(_shown + delta * CHARS_PER_SECOND, _page_chars)
			if _shown >= _page_chars:
				_finish_page()
			if int(_shown) != before:
				queue_redraw()
		State.READING:
			_read_timer -= delta
			if _read_timer <= 0.0:
				advance()
		State.CLOSING:
			_open = maxf(_open - delta / OPEN_TIME, 0.0)
			if _open <= 0.0:
				_state = State.HIDDEN
				closed.emit()
			queue_redraw()


func _start_typing() -> void:
	_state = State.TYPING
	_shown = 0.0
	_page_chars = 0
	for line in _pages[_page]:
		_page_chars += line.length()


func _finish_page() -> void:
	_state = State.READING
	_read_timer = READ_TIME + READ_TIME_PER_CHAR * _page_chars


## Sizes the balloon to the current page and places it under anchor,
## kept inside the screen, with the tail as near the middle as it can be.
func _layout() -> void:
	var widest := 0.0
	for line in _pages[_page]:
		widest = maxf(widest, _width(line, 4 * px))
	var lines := _pages[_page].size()
	var size := Vector2i(
			ceili(widest / px) + 2 * PAD_SIDE,
			ceili((lines - 1) * LINE_HEIGHT + CAP_HEIGHT + PAD_TOP + PAD_BOTTOM))
	var x := clampi(anchor.x - size.x / 2, MARGIN, SCREEN_WIDTH - MARGIN - size.x)
	_rect = Rect2i(Vector2i(x, anchor.y + TAIL), size)
	_tail_x = clampi(anchor.x, _rect.position.x + TAIL, _rect.end.x - TAIL - 1)


func _draw() -> void:
	if _state == State.HIDDEN:
		return
	var r := _rect
	if _state == State.OPENING or _state == State.CLOSING:
		# Grow out of the tail, a whole pixel at a time.
		var t := ease(_open, 0.5)
		var from := Rect2(_tail_x - TAIL, r.position.y, 2 * TAIL + 1, 3)
		r = Rect2i(Rect2(
				from.position.lerp(Vector2(r.position), t).round(),
				from.size.lerp(Vector2(r.size), t).round()))
	_draw_box(r)
	if _state == State.TYPING or _state == State.READING:
		_draw_text()


## A box with its corners cut round, and the tail: a wedge narrowing a
## pixel each side per row up to its tip.
func _draw_box(r: Rect2i) -> void:
	draw_rect(Rect2(r.position.x + 1, r.position.y, r.size.x - 2, r.size.y), FILL)
	draw_rect(Rect2(r.position.x, r.position.y + 1, r.size.x, r.size.y - 2), FILL)
	for row in range(1, TAIL + 1):
		var w := TAIL - row
		draw_rect(Rect2(_tail_x - w, r.position.y - row, 2 * w + 1, 1), FILL)


## The page's lines, each centred, cut off at however much has been typed.
func _draw_text() -> void:
	var font_size := 4 * px
	var half := px / 2.0
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE / px)
	var left := _shown
	var top := _rect.position.y + PAD_TOP - CAP_TOP
	for i in _pages[_page].size():
		if left <= 0:
			break
		var line := _pages[_page][i]
		var x := _rect.position.x + (_rect.size.x - _width(line, font_size) / px) / 2.0
		var baseline := (top + i * LINE_HEIGHT) * px + FONT.get_ascent(font_size)
		draw_string(FONT, Vector2(snappedf(x * px, half), snappedf(baseline, half)),
				line.left(int(left)), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, TEXT_COLOR)
		left -= line.length()
	draw_set_transform(Vector2.ZERO)
