extends SubViewportContainer
## Draws the game into a small buffer at twice the art's resolution and
## scales that up once, centred on the screen, instead of drawing every
## layer at the screen's full size, which weak GPUs can't keep up with.
## Twice the art's resolution is the finest anything is drawn at (covers,
## text on half pixels), so nothing is lost. Smoothing draws curves finer
## than that, so while it's on the buffer is drawn at the screen's own
## pixel size. Screens of another shape than the art get black bars.

## Screen units per buffer pixel: art pixels are 10 units wide, two buffer
## pixels each.
const UNITS_PER_PIXEL := 5

@onready var _view: SubViewport = $View


func _ready() -> void:
	get_viewport().size_changed.connect(_fit)
	SmoothPixels.toggled.connect(_fit.unbind(1))
	_fit()


## Sizes the buffer for the game area and centres it on the screen.
func _fit() -> void:
	var units := Vector2(
			ProjectSettings.get_setting("display/window/size/viewport_width"),
			ProjectSettings.get_setting("display/window/size/viewport_height"))
	# Window pixels per screen unit.
	var window_scale: float = get_tree().root.size.y / get_viewport_rect().size.y
	var pixels := units / UNITS_PER_PIXEL
	if SmoothPixels.enabled:
		pixels = (units * window_scale).round()
	_view.size = Vector2i(pixels)
	_view.size_2d_override = Vector2i(units)
	size = pixels
	scale = units / pixels
	# On a whole window pixel, so the upscaled pixels stay even.
	var margin := (Vector2(get_tree().root.size) - units * window_scale) / 2.0
	position = margin.round() / window_scale
