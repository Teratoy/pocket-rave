extends CanvasLayer
## Shows the two title cards over the game at launch: intro1 holds, fades
## into intro2, which holds and then fades away to reveal the game
## running underneath. Touches are swallowed until it is gone.

const INTRO1 := preload("res://visual assets/titles/intro1.png")
const INTRO2 := preload("res://visual assets/titles/intro2.png")

const HOLD1 := 0.2
const HOLD2 := 1.0
const FADE := 1.0


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	var second := _card(INTRO2)
	var first := _card(INTRO1)
	var tween := create_tween()
	tween.tween_interval(HOLD1)
	tween.tween_property(first, "modulate:a", 0.0, FADE)
	tween.tween_interval(HOLD2)
	tween.tween_property(second, "modulate:a", 0.0, FADE)
	tween.tween_callback(queue_free)


## A full-screen card that covers the viewport, cropping rather than
## letterboxing when the screen's aspect differs from the art's.
func _card(texture: Texture2D) -> TextureRect:
	var card := TextureRect.new()
	card.texture = texture
	card.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	card.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	card.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(card)
	return card
