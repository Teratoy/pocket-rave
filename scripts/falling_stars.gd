extends Sprite2D
## Every so often a falling star flashes somewhere in the sky and fades to
## black. Each one picks a random spot and a random facing. It sits just
## above the starfield, and never where the moon is, so it can't flash over
## her or hide behind her.

const TEXTURE := preload("res://visual assets/fallingstar.png")

## Top-left corner range for the star, in sky pixels. Keeps the whole
## 10x10 streak inside the open sky above the horizon.
const AREA := Rect2i(0, 0, 62, 66)

const WAIT_MIN := 4.0
const WAIT_MAX := 12.0
const HOLD := 0.15
const FADE := 0.4

## The streak's bright head is at the bottom-left of the texture, so it
## falls down and to the left; flipped, down and to the right.
const FALL := Vector2(-1, 1)

## Stars keep clear of this sprite's opaque pixels.
@export var moon: Sprite2D

var _moon_image: Image


func _ready() -> void:
	texture = TEXTURE
	centered = false
	visible = false
	if moon:
		_moon_image = moon.texture.get_image()
		if _moon_image.is_compressed():
			_moon_image.decompress()
	_next()


func _next() -> void:
	var tween := create_tween()
	tween.tween_interval(randf_range(WAIT_MIN, WAIT_MAX))
	tween.tween_callback(_show_star)
	tween.tween_interval(HOLD)
	tween.tween_property(self, "modulate", Color.BLACK, FADE)
	tween.parallel().tween_callback(_fall).set_delay(FADE / 2)
	tween.tween_callback(_hide_star)


func _show_star() -> void:
	flip_h = randf() < 0.5
	for i in 50:
		position = Vector2(
				randi_range(AREA.position.x, AREA.end.x),
				randi_range(AREA.position.y, AREA.end.y))
		if not _touches_moon():
			modulate = Color.WHITE
			visible = true
			return


## Steps the star one pixel along its path, partway through the fade.
func _fall() -> void:
	position += Vector2(-FALL.x if flip_h else FALL.x, FALL.y)


## Whether the streak, or the pixel it falls into, would cover any of the
## moon.
func _touches_moon() -> bool:
	if not _moon_image:
		return false
	var rect := Rect2i(Vector2i(position) - Vector2i.ONE, Vector2i(texture.get_size()) + Vector2i(2, 2))
	var offset := Vector2i(moon.position)
	var bounds := Rect2i(Vector2i.ZERO, _moon_image.get_size())
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var p := Vector2i(x, y) - offset
			if bounds.has_point(p) and _moon_image.get_pixelv(p).a > 0.0:
				return true
	return false


func _hide_star() -> void:
	visible = false
	_next()
