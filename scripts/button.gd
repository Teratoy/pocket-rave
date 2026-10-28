extends Sprite2D
## A UI button drawn as a full-screen sprite. Touching one of its opaque
## pixels presses it: the button and its glyph darken by 25% and the
## glyph sinks one pixel until the touch is released.

signal pressed

const PRESSED_TINT := Color(0.75, 0.75, 0.75)
const GLYPH_SINK := Vector2(0, 1)

var _glyph: Sprite2D
var _down := false


func _ready() -> void:
	for c in get_children():
		if c is Sprite2D:
			_glyph = c
			break


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.pressed:
		if is_pixel_opaque(to_local(get_canvas_transform().affine_inverse() * event.position)):
			_set_down(true)
			pressed.emit()
			get_viewport().set_input_as_handled()
	elif _down:
		_set_down(false)


func _set_down(down: bool) -> void:
	_down = down
	# Children inherit modulate, so this darkens the glyph too.
	modulate = PRESSED_TINT if down else Color.WHITE
	if _glyph:
		_glyph.position = GLYPH_SINK if down else Vector2.ZERO
