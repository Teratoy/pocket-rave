extends Node2D
## Shows the playing track's cover on the parent button. The button rises
## to fit the cover by repeating its bottom row of pixels; pressing it
## rises further to show the track, its artist (or the DJ when it has
## none) and playback time.
## Covers and text are drawn at twice the game resolution.

const FONT := preload("res://fonts/Silkscreen-Regular.ttf")
## One game pixel in screen pixels.
const PX := 10
## Half a game pixel: the size of one cover or font pixel.
const HALF := PX / 2
const FONT_SIZE := 4 * PX
const TEXT_COLOR := Color(0.9, 0.9, 0.9)
const BAR_BACK := Color(0.25, 0.25, 0.25)
const BAR_FILL := Color(0.9, 0.9, 0.9)

## Layout in game pixels, from the button's top row.
const COVER_TOP := 4
const COVER_SIZE := 18
const COVER_INSET := 3
const INFO_TOP := 23
const INFO_INSET := 2
const LINE_HEIGHT := 4
const BAR_TOP := 12
## Height the button takes on to show the cover, and then the info too.
const COVER_HEIGHT := COVER_TOP + COVER_SIZE + 2
const INFO_HEIGHT := INFO_TOP + BAR_TOP + 2

## Seconds per row while rising or sinking.
const RAISE_STEP := 0.015
## Seconds per half-pixel step of scrolling text.
const SCROLL_STEP := 0.08
const SCROLL_GAP := "   "

@export var music: Node

var _button: Sprite2D
var _base_img: Image
var _img: Image
var _tex: ImageTexture
var _rect: Rect2i
var _raise := 0
var _target := 0
var _step_timer := 0.0
var _scroll_timer := 0.0
var _has_track := false
var _expanded := false

var _cover: Sprite2D
var _info: Control
var _title: Label
var _artist: Label
var _time: Label
var _bar_fill: ColorRect


func _ready() -> void:
	_button = get_parent()
	_base_img = _button.texture.get_image()
	if _base_img.is_compressed():
		_base_img.decompress()
	_base_img.convert(Image.FORMAT_RGBA8)
	_rect = _base_img.get_used_rect()
	_img = _base_img.duplicate()
	_tex = ImageTexture.create_from_image(_img)
	_button.texture = _tex
	_build()
	_layout()
	music.track_started.connect(_on_track_started)
	music.playing_changed.connect(_on_playing_changed)
	_button.pressed.connect(_on_pressed)


func _process(delta: float) -> void:
	if _raise != _target:
		_step_timer -= delta
		if _step_timer <= 0.0:
			_step_timer = RAISE_STEP
			_raise += signi(_target - _raise)
			_redraw()
			_layout()
	if _info.visible:
		var pos: float = music.playback_position()
		var length: float = music.track_length()
		var time := "%d:%02d" % [int(pos) / 60, int(pos) % 60]
		if time != _time.text:
			_set_line(_time, time)
		var fill := 0.0 if length <= 0.0 else clampf(pos / length, 0.0, 1.0)
		_bar_fill.size.x = snappedf(fill * _info.size.x, HALF)
		_scroll_timer -= delta
		if _scroll_timer <= 0.0:
			_scroll_timer = SCROLL_STEP
			for l in [_title, _artist]:
				_scroll(l)


func _on_track_started(dj: String, title: String, artist: String, cover: Texture2D) -> void:
	_has_track = true
	_cover.texture = cover
	_set_line(_title, title.to_upper())
	_set_line(_artist, (artist if artist != "" else dj).to_upper())
	_target = _height_for_state() - _rect.size.y
	_layout()


func _on_playing_changed(playing: bool) -> void:
	if playing:
		return
	_has_track = false
	_expanded = false
	_target = 0
	_layout()


func _on_pressed() -> void:
	if not _has_track:
		return
	_expanded = not _expanded
	_target = _height_for_state() - _rect.size.y
	_layout()


func _height_for_state() -> int:
	return INFO_HEIGHT if _expanded else COVER_HEIGHT


## Moves the button's pixels up by _raise rows and fills the gap below
## with copies of its bottom row.
func _redraw() -> void:
	_img.fill(Color(0, 0, 0, 0))
	var top := _rect.position.y - _raise
	var bottom := _rect.end.y - 1
	for y in range(top, bottom + 1):
		var src := mini(y + _raise, bottom)
		_img.blit_rect(_base_img, Rect2i(0, src, _img.get_width(), 1), Vector2i(0, y))
	_tex.update(_img)


## Places the cover and info under the button's top edge. Each only shows
## once the button is tall enough to hold it.
func _layout() -> void:
	var top := _rect.position.y - _raise
	var height := _rect.size.y + _raise
	_cover.position = Vector2(_rect.position.x + COVER_INSET, top + COVER_TOP)
	_cover.visible = _has_track and _cover.texture != null \
			and height >= COVER_HEIGHT and _target >= COVER_HEIGHT - _rect.size.y
	_info.position = Vector2(_rect.position.x + INFO_INSET, top + INFO_TOP)
	_info.visible = _has_track and height >= INFO_HEIGHT and _expanded


func _build() -> void:
	_cover = Sprite2D.new()
	_cover.centered = false
	# Covers are 2x game resolution.
	_cover.scale = Vector2(0.5, 0.5)
	add_child(_cover)

	_info = Control.new()
	_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info.scale = Vector2.ONE / PX
	_info.size = Vector2((_rect.size.x - 2 * INFO_INSET) * PX, (BAR_TOP + 1) * PX)
	add_child(_info)

	_title = _add_line(0)
	_artist = _add_line(1)
	_time = _add_line(2)

	var back := ColorRect.new()
	back.color = BAR_BACK
	back.position = Vector2(0, BAR_TOP * PX)
	back.size = Vector2(_info.size.x, HALF)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info.add_child(back)
	_bar_fill = ColorRect.new()
	_bar_fill.color = BAR_FILL
	_bar_fill.size = Vector2(0, HALF)
	_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.add_child(_bar_fill)


## One line of text in a clipped strip, so long text can scroll through it.
func _add_line(row: int) -> Label:
	var clip := Control.new()
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.position = Vector2(0, row * LINE_HEIGHT * PX)
	clip.size = Vector2(_info.size.x, LINE_HEIGHT * PX)
	_info.add_child(clip)
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", FONT)
	l.add_theme_font_size_override("font_size", FONT_SIZE)
	l.add_theme_color_override("font_color", TEXT_COLOR)
	# Lift the caps to the top of the strip; Silkscreen leaves room above them.
	l.position.y = -3 * HALF
	clip.add_child(l)
	return l


## Short text sits centred; text wider than the strip scrolls, repeated.
func _set_line(l: Label, text: String) -> void:
	var width := _text_width(text)
	if width <= _info.size.x:
		l.text = text
		l.position.x = snappedf((_info.size.x - width) / 2.0, HALF)
		l.set_meta("loop", 0.0)
	else:
		l.text = text + SCROLL_GAP + text
		l.position.x = 0.0
		l.set_meta("loop", _text_width(text + SCROLL_GAP))
	l.size = Vector2.ZERO


func _scroll(l: Label) -> void:
	var loop: float = l.get_meta("loop", 0.0)
	if loop <= 0.0:
		return
	l.position.x -= HALF
	if -l.position.x >= loop:
		l.position.x += loop


func _text_width(text: String) -> float:
	return FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
